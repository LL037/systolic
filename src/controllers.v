
module top_ctrl_nn #(
    parameter N = 4   // Matrix dimension (must be divisible by 4)
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       start,

    // Handshakes from sub-controllers
    input  wire       valid_ctrl_busy,
    input  wire       layer_ctrl_busy,
    input  wire       next_tile_ready,

    output reg                    next_tile,     
    output reg  [2:0]             mode,          // 0:idle 1:load 2:layer
    output reg                    start_valid_pipeline,
    output reg                    start_layering,
    output reg                    start_weights,
    output reg                    start_input,
    output reg                    done
);

    localparam NUM_TILES = N / 4;  // number of row_tile iterations

    localparam [2:0]
        MODE_IDLE  = 3'd0,
        MODE_LOAD  = 3'd1,
        MODE_LAYER = 3'd2;

    localparam [3:0]
        S_IDLE           = 4'd0,
        S_ISSUE_LOAD     = 4'd1,
        S_WAIT_LOAD_ON   = 4'd2,
        S_WAIT_LOAD_OFF  = 4'd3,
        S_NEXT_LOAD_TILE = 4'd4,
        S_ISSUE_LAYER    = 4'd5,
        S_WAIT_LAY_ON    = 4'd6,
        S_WAIT_LAY_OFF   = 4'd7,
        S_NEXT_LAY_TILE  = 4'd8,
        S_DONE           = 4'd9;

    reg [3:0] state;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state                <= S_IDLE;
            mode                 <= MODE_IDLE;
            start_valid_pipeline <= 1'b0;
            start_layering       <= 1'b0;
            start_weights        <= 1'b0;
            start_input          <= 1'b0;
            done                 <= 1'b0;
        end else begin
            // Default: 1-cycle pulses
            start_valid_pipeline <= 1'b0;
            start_layering       <= 1'b0;
            start_weights        <= 1'b0;
            start_input          <= 1'b0;
            done                 <= 1'b0;

            case (state)
                // ---------------------------------------------------------
                S_IDLE: begin
                    mode          <= MODE_IDLE;
        
                    if (start && !valid_ctrl_busy && !layer_ctrl_busy)
                        state <= S_ISSUE_LOAD;
                end
                // loading
                S_ISSUE_LOAD: begin
                    mode                 <= MODE_LOAD;
                    start_weights        <= 1'b1;
                    start_input          <= 1'b1;
                    start_valid_pipeline <= 1'b1;
                    state                <= S_WAIT_LOAD_ON;
                end

                S_WAIT_LOAD_ON: begin
                    mode <= MODE_LOAD;
                    if (valid_ctrl_busy)
                        state <= S_WAIT_LOAD_OFF;
                end

                S_WAIT_LOAD_OFF: begin
                    mode <= MODE_LOAD;
                    if (!valid_ctrl_busy && next_tile_ready)
                        state <= S_NEXT_LOAD_TILE;
                end
                // next tile 
                S_NEXT_LOAD_TILE: begin
                    mode <= MODE_LOAD;
                    if (!valid_ctrl_busy)
                        state <= S_ISSUE_LOAD;
                end

                S_ISSUE_LAYER: begin
                    mode           <= MODE_LAYER;
                    start_layering <= 1'b1;
                    state          <= S_WAIT_LAY_ON;
                end

                S_WAIT_LAY_ON: begin
                    mode <= MODE_LAYER;
                    if (layer_ctrl_busy)
                        state <= S_WAIT_LAY_OFF;
                end

                S_WAIT_LAY_OFF: begin
                    mode <= MODE_LAYER;
                    if (!layer_ctrl_busy)
                        state <= S_DONE;
                end


                // ---------------------------------------------------------
                S_DONE: begin
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule


module layering_pipeline_ctrl_nn (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire        layer_ready,
    output reg  [11:0] valid_ctrl,
    output reg         busy
);
    localparam IDLE   = 2'd0;
    localparam S_WAIT = 2'd1;
    localparam S_LOAD0= 2'd2;
    localparam S_SWAP0= 2'd3;

    reg [1:0] state, next_state;

    always @(posedge clk) begin
        if (rst)  state <= IDLE;
        else      state <= next_state;
    end

    always @(*) begin
        next_state = state;
        case (state)
            IDLE:    next_state = start       ? S_WAIT  : IDLE;
            S_WAIT:  next_state = layer_ready ? S_LOAD0 : S_WAIT;
            S_LOAD0: next_state = S_SWAP0;
            S_SWAP0: next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    // valid_ctrl: drive mac_0/mac_1 with a_in_1 (acc feedback) in S_LOAD0
    //             drive mac_2/mac_3 with a_in_1 in S_SWAP0
    always @(*) begin
        case (state)
            S_LOAD0: valid_ctrl = 12'b001001000000; // mac_0 a_in_1, mac_1 a_in_1
            S_SWAP0: valid_ctrl = 12'b010010000000; // mac_2 a_in_1, mac_3 a_in_1
            default: valid_ctrl = 12'b000000000000;
        endcase
    end

    always @(posedge clk) begin
        if (rst) busy <= 1'b0;
        else     busy <= (next_state != IDLE);
    end

endmodule


module valid_pipeline_ctrl_nn #(
    parameter N = 4   // must match matrix size
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,       // 1-cycle pulse to begin
    input  wire        load_ready,  // handshake from weight_mem_if
    output reg  [11:0] valid_ctrl,
    output reg         busy
);

    reg [$clog2(N+2):0] cnt;        // count N cycles of activation
    reg                  running;
    reg                  armed;

    // valid_ctrl encoding for mac_0: bit0=a_in_0
    // valid_ctrl encoding for mac_1: bit0=a_in_0 (= mac_0.a_out_0, 1-cycle late)
    // During load, only tile-1 pair is active (mac_0, mac_1)

    always @(posedge clk) begin
        if (rst) begin
            cnt       <= 0;
            running   <= 1'b0;
            armed     <= 1'b0;
            busy      <= 1'b0;
            valid_ctrl <= 12'd0;
        end else begin
            if (start)  armed <= 1'b1;
            if (load_ready && armed) begin
                running <= 1'b1;
                armed   <= 1'b0;
                cnt     <= 0;
            end

            if (running) begin
                cnt <= cnt + 1;

                // mac_0 active for cycles 0..N-1
                // mac_1 active for cycles 1..N (1 cycle offset due to pass-through)
                // packed: {mac3[2:0], mac2[2:0], mac1[2:0], mac0[2:0]}
                valid_ctrl[2:0]  <= (cnt < N)   ? 3'b001 : 3'b000;  // mac_0 a_in_0
                valid_ctrl[5:3]  <= (cnt > 0 && cnt <= N) ? 3'b001 : 3'b000; // mac_1
                valid_ctrl[11:6] <= 6'b000000;  // tile2 not in load phase

                if (cnt == N + 1) begin
                    running    <= 1'b0;
                    valid_ctrl <= 12'd0;
                end
            end else begin
                valid_ctrl <= 12'd0;
            end

            busy <= running || armed;
        end
    end

endmodule



module weight_pipeline_ctrl_nn #(
    parameter N_MACS = 4
)(
    input  wire         clk,
    input  wire         rst,
    input  wire         start,
    input  wire [2:0]   mode,       // 0:idle 1:load 2:layer

    output reg  [N_MACS-1:0] weight_ctrl,
    output reg  [2:0]        load,
    output reg               busy,
    output reg               load_ready,
    output reg               layer_ready
);
    localparam IDLE  = 2'd0;
    localparam LOAD  = 2'd1;
    localparam LAYER = 2'd2;

    reg [1:0] state, next_state;
    reg [2:0] prev_mode;
    reg [2:0] load_pulse;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state      <= IDLE;
            prev_mode  <= 3'd0;
            load_pulse <= 3'b000;
        end else begin
            state      <= next_state;
            load_pulse <= 3'b000;
            if (mode != prev_mode) begin
                if      (mode == 3'd1) load_pulse <= 3'b001;
                else if (mode == 3'd2) load_pulse <= 3'b010;
            end
            prev_mode <= mode;
        end
    end

    always @(*) begin
        next_state = state;
        if (mode == 3'd0)          next_state = IDLE;
        else if (mode != prev_mode) begin
            case (mode)
                3'd1:    next_state = LOAD;
                3'd2:    next_state = LAYER;
                default: next_state = state;
            endcase
        end
    end

    always @(*) begin
        weight_ctrl = {N_MACS{1'b0}};
        busy        = 1'b0;
        load_ready  = 1'b0;
        layer_ready = 1'b0;
        load        = load_pulse;
        case (state)
            LOAD:  begin
                weight_ctrl = {N_MACS{1'b1}};  // all 4 MACs receive weights
                load_ready  = 1'b1;
                busy        = 1'b1;
            end
            LAYER: begin
                weight_ctrl = {N_MACS{1'b0}};  // no weights during readout
                layer_ready = 1'b1;
                busy        = 1'b1;
            end
            default: ;
        endcase
    end

endmodule


module tile_ctrl_nn #(
    parameter N_MACS = 4
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        next_tile,
    output reg         next_tile_ready,
    output reg [2:0]   acc_sel_tile
);

    localparam IDLE  = 2'd0;
    localparam INCR  = 2'd1;
    localparam READY = 2'd2;

    reg [1:0] state, next_state;
    reg [2:0] tile_cnt;

    // State register
    always @(posedge clk or posedge rst) begin
        if (rst) state <= IDLE;
        else     state <= next_state;
    end

    // Next-state logic
    always @(*) begin
        next_state = state;
        case (state)
            IDLE:  if (next_tile) next_state = INCR;
            INCR:                 next_state = READY;
            READY:                next_state = IDLE;
            default:              next_state = IDLE;
        endcase
    end

    // Output + counter
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            tile_cnt        <= 3'd0;
            acc_sel_tile    <= 3'd0;
            next_tile_ready <= 1'b0;
        end else begin
            next_tile_ready <= 1'b0;
            case (state)
                INCR: begin
                    acc_sel_tile <= tile_cnt;
                    
                    if (tile_cnt == N_MACS - 1)
                        tile_cnt <= 3'd0;
                    else
                        tile_cnt <= tile_cnt + 3'd1;
                end
                READY: begin
                    next_tile_ready <= 1'b1;
                end
                default: ;
            endcase
        end
    end

endmodule