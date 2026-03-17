module top_ctrl #(
    parameter N = 4
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       start,

    input  wire       valid_ctrl_busy,
    input  wire       layer_ctrl_busy,
    input  wire       input_if_valid,
    input  wire       weight_if_valid,

    output reg  [2:0]             tile_number,
    output reg  [2:0]             mode,
    output reg                    start_valid_pipeline,
    output reg                    start_layering,
    output reg                    start_weights,
    output reg                    start_input,
    output reg                    done,

    output reg                    prime_input_en,
    output reg                    prime_weight_en
);

    localparam NUM_TILES = N / 2;

    localparam [2:0]
        MODE_IDLE  = 3'd0,
        MODE_LOAD  = 3'd1,
        MODE_LAYER = 3'd2;

    localparam [3:0]
        S_IDLE            = 4'd0,
        S_ISSUE_LOAD      = 4'd1,
        S_WAIT_VALID_HIGH = 4'd2,   // ◀ 改名：等 weight_if_valid 拉高
        S_WAIT_VALID_LOW  = 4'd3,   // ◀ 改名：等 weight_if_valid 落下
        S_DECIDE          = 4'd4,
        S_ISSUE_LAYER     = 4'd5,
        S_WAIT_LAY_ON     = 4'd6,
        S_WAIT_LAY_OFF    = 4'd7,
        S_DONE            = 4'd8,
        S_PRIME           = 4'd9,
        S_PRIME_DONE      = 4'd10;

    reg [3:0] state;

    wire [2:0] next_tile = tile_number + 1'b1;
    wire all_tiles_done  = (next_tile >= NUM_TILES[2:0]);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state                <= S_PRIME;
            mode                 <= MODE_IDLE;
            start_valid_pipeline <= 1'b0;
            start_layering       <= 1'b0;
            start_weights        <= 1'b0;
            start_input          <= 1'b0;
            done                 <= 1'b0;
            tile_number          <= 3'd0;
            prime_input_en       <= 1'b0;
            prime_weight_en      <= 1'b0;
        end else begin
            start_valid_pipeline <= 1'b0;
            start_layering       <= 1'b0;
            start_weights        <= 1'b0;
            start_input          <= 1'b0;
            done                 <= 1'b0;
            prime_input_en       <= 1'b0;
            prime_weight_en      <= 1'b0;

            case (state)

                S_PRIME: begin
                    mode            <= MODE_IDLE;
                    prime_input_en  <= 1'b1;
                    prime_weight_en <= 1'b1;
                    state           <= S_PRIME_DONE;
                end

                S_PRIME_DONE: begin
                    mode  <= MODE_IDLE;
                    state <= S_IDLE;
                end

                S_IDLE: begin
                    mode        <= MODE_IDLE;
                    tile_number <= 3'd0;
                    if (start && !valid_ctrl_busy && !layer_ctrl_busy)
                        state <= S_ISSUE_LOAD;
                end

                S_ISSUE_LOAD: begin
                    mode                 <= MODE_LOAD;
                    start_weights        <= 1'b1;
                    start_input          <= 1'b1;
                    start_valid_pipeline <= 1'b1;
                    state                <= S_WAIT_VALID_HIGH;
                end

                // ── 等 weight_mem_if 开始输出（valid 拉高）────
                S_WAIT_VALID_HIGH: begin
                    mode <= MODE_LOAD;
                    if (weight_if_valid)
                        state <= S_WAIT_VALID_LOW;
                end

                // ── 等 weight_mem_if 输出完毕（valid 落下）────
                S_WAIT_VALID_LOW: begin
                    mode <= MODE_LOAD;
                    if (!weight_if_valid)
                        state <= S_DECIDE;
                end

                S_DECIDE: begin
                    mode <= MODE_IDLE;
                    if (all_tiles_done) begin
                        state <= S_ISSUE_LAYER;
                    end else begin
                        tile_number <= next_tile;
                        state       <= S_ISSUE_LOAD;
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


module valid_pipeline_ctrl #(
    parameter integer N = 4
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire        load_ready,
    output wire [11:0] valid_ctrl,
    output reg         busy
);
    localparam integer CNT_MAX = N;

    reg [$clog2(N+2)-1:0] cnt;
    reg                    running;
    reg                    armed;

    // --- combinational output: zero latency from state ---
    wire launching = armed && load_ready;
    wire active    = running || launching;

    assign valid_ctrl[0]    = active && (cnt < N);
    assign valid_ctrl[3]    = active && (cnt > 0);
    assign valid_ctrl[2:1]  = 2'b0;
    assign valid_ctrl[11:4] = 8'b0;

    // --- sequential state ---
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cnt     <= 0;
            running <= 1'b0;
            armed   <= 1'b0;
            busy    <= 1'b0;
        end else begin
            if (start)
                armed <= 1'b1;

            if (launching) begin
                armed   <= 1'b0;
                running <= 1'b1;
                cnt     <= 1;
            end else if (running) begin
                if (cnt == CNT_MAX) begin
                    running <= 1'b0;
                    cnt     <= 0;
                end else begin
                    cnt <= cnt + 1;
                end
            end

            busy <= running || armed || launching;
        end
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



