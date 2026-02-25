
module top_ctrl #(
    parameter N = 8   // Matrix dimension (must be divisible by 4)
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       start,

    // Handshakes from sub-controllers
    input  wire       valid_ctrl_busy,
    input  wire       layer_ctrl_busy,
    input  wire       next_tile_ready,
    input  wire       load_tile_done,

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
            next_tile            <= 1'b0;
            done                 <= 1'b0;
        end else begin
            // Default: 1-cycle pulses
            start_valid_pipeline <= 1'b0;
            start_layering       <= 1'b0;
            start_weights        <= 1'b0;
            start_input          <= 1'b0;
            next_tile            <= 1'b0;
            done                 <= 1'b0;

            case (state)

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
                    if (!valid_ctrl_busy)
                        state <= S_NEXT_LOAD_TILE;
                end
                // next tile 
                S_NEXT_LOAD_TILE: begin
                    mode      <= MODE_LOAD;
                    next_tile <= 1'b1;
                    if (!valid_ctrl_busy) begin
                        if (load_tile_done)      
                            state <= S_ISSUE_LAYER;
                        else
                            state <= S_ISSUE_LOAD;
                    end
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

                S_DONE: begin
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule


module layering_pipeline_ctrl (
    input  wire       clk,
    input  wire       rst,
    input  wire       start,
    input  wire       layer_ready,   // handshake: only start when ready
    output reg  [11:0] valid_ctrl,
    output reg        busy
);
    localparam IDLE   = 4'd0;
    localparam S_WAIT = 4'd1;   // NEW: wait for layer_ready after start
    localparam S_LOAD0= 4'd2;
    localparam S_SWAP0= 4'd4; 
 
     
    reg [3:0] state, next_state;

    always @(posedge clk) begin
        if (rst)
            state <= IDLE;
        else
            state <= next_state;
    end

    always @(*) begin
        next_state = state;
        case (state)
            IDLE:    next_state = start ? S_WAIT  : IDLE;
            S_WAIT:  next_state = layer_ready ? S_LOAD0 : S_WAIT;

            S_LOAD0: next_state = S_SWAP0;
            S_SWAP0: next_state = IDLE;

            default: next_state = IDLE;
        endcase
    end

    always @(*) begin
        valid_ctrl = 12'b000000000000;
        case (state)
            S_LOAD0: valid_ctrl = 12'b001001000000; 
            S_SWAP0: valid_ctrl = 12'b010010000000;
            default: valid_ctrl = 12'b000000000000;
        endcase
    end

    always @(posedge clk) begin
        if (rst)
            busy <= 1'b0;
        else
            busy <= (next_state != IDLE);
    end

endmodule


module valid_pipeline_ctrl (
    input  wire       clk,
    input  wire       rst,
    input  wire       start,
    input  wire       load_ready,
    output reg  [11:0] valid_ctrl, 
    output reg        busy        
);

    reg [5:0] valid_shift;
    reg [1:0] start_tok;   // CHANGED: 2-bit token "11"
    reg       armed;

    always @(posedge clk) begin
        if (rst) begin
            valid_shift <= 6'b000000;
            start_tok   <= 2'b00;
            armed       <= 1'b0;
            busy        <= 1'b0;
        end else begin
            // latch a 2-cycle token on start
            if (start) start_tok <= 2'b11;

            // allow running once ready
            if (load_ready) armed <= 1'b1;

            if (armed || load_ready) begin
                // inject token LSB into tap0 (gives 2 cycles of '1')
                valid_shift[0] <= start_tok[0];
                valid_shift[3] <= valid_shift[0];

                // shift token down (natural decay in 2 cycles)
                start_tok <= {1'b0, start_tok[1]};
            end

            busy <= (|start_tok) | valid_shift[0] | valid_shift[3];

            if (busy == 1'b0)
                armed <= 1'b0;
        end
    end

    always @(*) begin
        valid_ctrl = {3'b000,3'b000,2'b00, valid_shift[3],2'b00, valid_shift[0]};
    end

endmodule


module weight_pipeline_ctrl #(
    parameter N_MACS = 4

)(
    input  wire       clk,
    input  wire       rst,
    input  wire       start,

    input  wire [2:0]      mode, // 0: idle, 1: load weights, 2: layering

    output reg  [N_MACS-1:0] weight_ctrl, 
    output reg  [2:0] load,
    output reg        busy,
    output reg  load_ready,
    output reg  layer_ready       
);
// FSM states
localparam IDLE  = 2'd0;
localparam LOAD  = 2'd1;
localparam LAYER = 2'd2;

// masks for N_MACS (for N_MACS==4 yields 4'b0011 and 4'b1100)
localparam integer HALF_W = N_MACS / 2;
localparam [N_MACS-1:0] LOAD_MASK  = ((1 << HALF_W) - 1);
localparam [N_MACS-1:0] LAYER_MASK = (LOAD_MASK << HALF_W);

reg [1:0] state, next_state;
reg [2:0] prev_mode;
reg [2:0] load_pulse;


// state register and remember previous mode
always @(posedge clk or posedge rst) begin
    if (rst) begin
        state     <= IDLE;
        prev_mode <= 3'd0;
        load_pulse <= 3'b000;
    end else begin
        state     <= next_state;
        load_pulse <= 3'b000;
        if (mode != prev_mode) begin  
            if (mode == 3'd1)      load_pulse <= 3'b001; 
            else if (mode == 3'd2) load_pulse <= 3'b010; 
        end

        prev_mode <= mode;
    end
end
// next state logic
always @(*) begin
    next_state = state;
    if (mode == 3'd0) begin
        next_state = IDLE;
    end else if (mode != prev_mode) begin
        case (mode)
            3'd1: next_state = LOAD;
            3'd2: next_state = LAYER;
            default: next_state = state;
        endcase
    end
end

// outputs based on current state
always @(*) begin
    weight_ctrl = {N_MACS{1'b0}};
    busy        = 1'b0;
    load_ready = 1'b0;
    layer_ready = 1'b0;
    load        = load_pulse; 
    case (state)
        IDLE: begin
            weight_ctrl = {N_MACS{1'b0}};
            busy        = 1'b0;
        end
        LOAD: begin
            weight_ctrl = LOAD_MASK;   // 4'b0011 
            load_ready = 1'b1;
            busy        = 1'b1;
        end
        LAYER: begin
            weight_ctrl = LAYER_MASK;  //  4'b1100 
            layer_ready = 1'b1;
            busy        = 1'b1;
        end
        default: begin
            weight_ctrl = {N_MACS{1'b0}};

            busy        = 1'b0;
        end
    endcase
end

endmodule

module tile_ctrl #(
    parameter N_MACS = 8
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        next_tile,

    output reg         next_tile_ready,
    output reg [2:0]   acc_sel_tile,
    output reg         load_tile_done    
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
            next_tile_ready <= 1'b1;
            load_tile_done  <= 1'b0;    
        end else begin
            next_tile_ready <= 1'b0;
            load_tile_done  <= 1'b0;    
            case (state)
                INCR: begin
                    acc_sel_tile <= tile_cnt;
                    
                    if (tile_cnt == N_MACS - 1) begin
                        tile_cnt       <= 3'd0;
                        load_tile_done <= 1'b1;  
                    end else begin
                        tile_cnt <= tile_cnt + 3'd1;
                    end
                end
                READY: begin
                    next_tile_ready <= 1'b1;
                end
                default: ;
            endcase
        end
    end

endmodule