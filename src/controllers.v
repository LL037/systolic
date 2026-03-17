// =============================================================
//  top_ctrl.v  —  fully generalized FSM
//
//  Parameters:
//    N           : input vector size = matrix dim
//    N_COLS      : MACs per row (M)
//    N_ROWS      : number of layers (L)
//    NUM_ACC     : accumulator banks per MAC (>= T = N/N_COLS)
//    LAYER_BASES : packed array of L base addresses for L1..LL weights
//                  [7:0] per layer, packed as [8*N_ROWS-1:0]
//                  layer i base = LAYER_BASES[8*(i+1)-1 : 8*i]
//
//  FSM flow:
//
//  RESET → S_PRIME → S_PRIME_DONE → S_IDLE
//
//  ── Phase 0: Layer 1 Load (Row 0 systolic) ───────────────────
//  S_IDLE → S_ISSUE_LOAD
//         → S_WAIT_VALID_HIGH → S_WAIT_VALID_LOW
//         → S_DECIDE_L1_TILE
//               ├─ more L1 tiles → tile_number++ → S_ISSUE_LOAD
//               └─ all L1 tiles done → layer_idx=1, layer_tile=0
//                                    → S_ISSUE_LAYER_TILE
//
//  ── Phase 1..L-1: Layer Compute (Row 1..L-1) ─────────────────
//  S_ISSUE_LAYER_TILE
//         → S_WAIT_LAY_ON → S_WAIT_LAY_OFF
//         → S_DECIDE_LAYER_TILE
//               ├─ more layer tiles → layer_tile++ → S_ISSUE_LAYER_TILE
//               └─ all tiles done → S_DECIDE_LAYER
//                       ├─ more layers → layer_idx++ → S_ISSUE_LAYER_TILE
//                       └─ all layers done → S_DONE
//
//  S_DONE → S_IDLE
//
//  Outputs:
//    tile_number      : L1 tile index (→ weight_base_addr = tile*N_COLS)
//    layer_tile       : L2..LL tile index
//    layer_idx        : current layer being computed (1..N_ROWS-1)
//    weight_base_addr : current effective base address for weight_mem_if
//    active_row       : which row's layering_ctrl to enable (one-hot, N_ROWS bits)
// =============================================================
module top_ctrl #(
    parameter N           = 8,
    parameter N_COLS      = 4,
    parameter N_ROWS      = 2,
    parameter NUM_ACC     = 8,
    parameter [8*N_ROWS-1:0] LAYER_BASES = {8'd32, 8'd0}
    // LAYER_BASES[7:0]   = layer 0 base (L1 load weights)
    // LAYER_BASES[15:8]  = layer 1 base (L2 compute weights)
    // etc.
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       start,

    input  wire       valid_ctrl_busy,
    input  wire       layer_ctrl_busy,     // OR of all layering_ctrl busy
    input  wire       input_if_valid,
    input  wire       weight_if_valid,

    // L1 load tile
    output reg  [$clog2(NUM_ACC)-1:0]  tile_number,

    // L2..LL compute
    output reg  [$clog2(NUM_ACC)-1:0]  layer_tile,
    output reg  [$clog2(N_ROWS)-1:0]   layer_idx,        // 1..N_ROWS-1

    // effective weight base address (muxed L1/L2+)
    output reg  [7:0]                  weight_base_addr,

    // one-hot: which row's layering_ctrl gets start pulse
    output reg  [N_ROWS-1:0]           active_row,

    output reg  [2:0]                  mode,
    output reg                         start_valid_pipeline,
    output reg                         start_layering,
    output reg                         start_weights,
    output reg                         start_input,
    output reg                         done,

    output reg                         prime_input_en,
    output reg                         prime_weight_en
);

    // ── derived constants ─────────────────────────────────────
    localparam T = N / N_COLS;   // tiles per layer

    localparam [2:0]
        MODE_IDLE  = 3'd0,
        MODE_LOAD  = 3'd1,
        MODE_LAYER = 3'd2;

    localparam [3:0]
        S_IDLE              = 4'd0,
        S_PRIME             = 4'd1,
        S_PRIME_DONE        = 4'd2,
        S_ISSUE_LOAD        = 4'd3,
        S_WAIT_VALID_HIGH   = 4'd4,
        S_WAIT_VALID_LOW    = 4'd5,
        S_DECIDE_L1_TILE    = 4'd6,
        S_ISSUE_LAYER_TILE  = 4'd7,
        S_WAIT_LAY_ON       = 4'd8,
        S_WAIT_LAY_OFF      = 4'd9,
        S_DECIDE_LAYER_TILE = 4'd10,
        S_DECIDE_LAYER      = 4'd11,
        S_DONE              = 4'd12;

    reg [3:0] state;

    // ── tile / layer bounds ───────────────────────────────────
    wire l1_tile_last    = (tile_number  == T - 1);
    wire layer_tile_last = (layer_tile   == T - 1);
    wire layer_last      = (layer_idx    == N_ROWS - 1);

    // ── layer base address lookup ─────────────────────────────
    // LAYER_BASES[8*(i+1)-1 : 8*i] = base for layer i
    function [7:0] get_layer_base;
        input [$clog2(N_ROWS)-1:0] idx;
        integer fi;
        begin
            get_layer_base = 8'd0;
            for (fi = 0; fi < N_ROWS; fi = fi + 1)
                if (fi == idx)
                    get_layer_base = LAYER_BASES[8*(fi+1)-1 -: 8];
        end
    endfunction

    // ─────────────────────────────────────────────────────────
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state                <= S_PRIME;
            mode                 <= MODE_IDLE;
            tile_number          <= 0;
            layer_tile           <= 0;
            layer_idx            <= 0;
            weight_base_addr     <= get_layer_base(0);
            active_row           <= 0;
            start_valid_pipeline <= 0;
            start_layering       <= 0;
            start_weights        <= 0;
            start_input          <= 0;
            done                 <= 0;
            prime_input_en       <= 0;
            prime_weight_en      <= 0;
        end else begin
            // default: pulse signals low
            start_valid_pipeline <= 0;
            start_layering       <= 0;
            start_weights        <= 0;
            start_input          <= 0;
            done                 <= 0;
            prime_input_en       <= 0;
            prime_weight_en      <= 0;
            active_row           <= 0;

            case (state)

                // ── BRAM priming ─────────────────────────────
                S_PRIME: begin
                    mode            <= MODE_IDLE;
                    prime_input_en  <= 1;
                    prime_weight_en <= 1;
                    state           <= S_PRIME_DONE;
                end

                S_PRIME_DONE: begin
                    mode  <= MODE_IDLE;
                    state <= S_IDLE;
                end

                // ── wait for start ───────────────────────────
                S_IDLE: begin
                    mode             <= MODE_IDLE;
                    tile_number      <= 0;
                    layer_tile       <= 0;
                    layer_idx        <= 1;  // layer 0 = load; compute starts at 1
                    weight_base_addr <= get_layer_base(0);
                    if (start && !valid_ctrl_busy && !layer_ctrl_busy)
                        state <= S_ISSUE_LOAD;
                end

                // ── L1 load: issue one tile ───────────────────
                S_ISSUE_LOAD: begin
                    mode                 <= MODE_LOAD;
                    weight_base_addr     <= get_layer_base(0) +
                                           {{(8-$clog2(NUM_ACC)){1'b0}}, tile_number}
                                           * N_COLS[7:0];
                    start_weights        <= 1;
                    start_input          <= 1;
                    start_valid_pipeline <= 1;
                    state                <= S_WAIT_VALID_HIGH;
                end

                S_WAIT_VALID_HIGH: begin
                    mode <= MODE_LOAD;
                    if (weight_if_valid)
                        state <= S_WAIT_VALID_LOW;
                end

                S_WAIT_VALID_LOW: begin
                    mode <= MODE_LOAD;
                    if (!weight_if_valid)
                        state <= S_DECIDE_L1_TILE;
                end

                // ── L1 tile decision ──────────────────────────
                S_DECIDE_L1_TILE: begin
                    mode <= MODE_IDLE;  // clears weight_mem_if ran flag
                    if (l1_tile_last) begin
                        // all L1 tiles done → start L2
                        layer_idx        <= 1;
                        layer_tile       <= 0;
                        weight_base_addr <= get_layer_base(1);
                        state            <= S_ISSUE_LAYER_TILE;
                    end else begin
                        tile_number <= tile_number + 1;
                        state       <= S_ISSUE_LOAD;
                    end
                end

                // ── Layer compute: issue one tile ─────────────
                S_ISSUE_LAYER_TILE: begin
                    mode                   <= MODE_LAYER;
                    // base = layer_base[layer_idx] + layer_tile * N_COLS * 2
                    // (*2 because MODE_LAYER uses stride-2 BRAM access)
                    weight_base_addr       <= get_layer_base(layer_idx) +
                                             {{(8-$clog2(NUM_ACC)){1'b0}}, layer_tile}
                                             * (N_COLS[7:0] * 8'd2);
                    // one-hot: enable only the current layer's row controller
                    active_row             <= (1 << layer_idx);
                    start_weights          <= 1;
                    start_layering         <= 1;
                    state                  <= S_WAIT_LAY_ON;
                end

                S_WAIT_LAY_ON: begin
                    mode <= MODE_LAYER;
                    if (layer_ctrl_busy)
                        state <= S_WAIT_LAY_OFF;
                end

                S_WAIT_LAY_OFF: begin
                    mode <= MODE_LAYER;
                    if (!layer_ctrl_busy)
                        state <= S_DECIDE_LAYER_TILE;
                end

                // ── Layer tile decision ───────────────────────
                S_DECIDE_LAYER_TILE: begin
                    mode <= MODE_IDLE;  // clears weight_mem_if ran flag
                    if (layer_tile_last) begin
                        state <= S_DECIDE_LAYER;
                    end else begin
                        layer_tile       <= layer_tile + 1;
                        // advance weight base for next tile
                        weight_base_addr <= get_layer_base(layer_idx) +
                                           ({{(8-$clog2(NUM_ACC)){1'b0}}, layer_tile} + 1)
                                           * (N_COLS[7:0] * 8'd2);
                        state            <= S_ISSUE_LAYER_TILE;
                    end
                end

                // ── Layer decision: advance to next layer ─────
                S_DECIDE_LAYER: begin
                    mode <= MODE_IDLE;
                    if (layer_last) begin
                        state <= S_DONE;
                    end else begin
                        layer_idx        <= layer_idx + 1;
                        layer_tile       <= 0;
                        weight_base_addr <= get_layer_base(layer_idx + 1);
                        state            <= S_ISSUE_LAYER_TILE;
                    end
                end

                // ── done ─────────────────────────────────────
                S_DONE: begin
                    done  <= 1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule
// =============================================================
//  layering_pipeline_ctrl.v  —  generalized for N_COLS MACs, T tiles
//
//  Controls ONE layer row computation.
//  Called once per layer by top_ctrl; top_ctrl loops over layers.
//
//  Per tile (rd_sel = tile index):
//    step 1      : valid_ctrl = a_in_0 for all N_COLS MACs
//    step 2..M   : valid_ctrl = a_in_1 for all N_COLS MACs (ring shift)
//
//  Total steps per tile = N_COLS (= M)
//  Total tiles per layer = N_TILES
//  Total steps per layer = N_TILES * N_COLS
//
//  rd_sel increments each tile: tile k → rd_sel = k
//  rd_sel width = $clog2(NUM_ACC)
//
//  valid_ctrl width = 3 * N_COLS (for ONE row, one layer)
//  top_ctrl places this into the correct row slice of the
//  full valid_ctrl bus.
// =============================================================
module layering_pipeline_ctrl #(
    parameter N_COLS  = 4,    // M: MACs per row
    parameter N_TILES = 2,    // T = N/M: tiles per layer
    parameter NUM_ACC = 8     // must match mac.v NUM_ACC
)(
    input  wire                          clk,
    input  wire                          rst,
    input  wire                          start,
    input  wire                          layer_ready,   // from weight_pipeline_ctrl

    output reg  [3*N_COLS-1:0]           valid_ctrl,    // for ONE row
    output reg  [$clog2(NUM_ACC)-1:0]    rd_sel,        // tile index → acc bank
    output reg                           busy
);

    // ── state encoding ───────────────────────────────────────
    // S_IDLE, S_WAIT, then N_COLS steps per tile, N_TILES tiles
    // We use a step counter and tile counter instead of
    // enumerating all N_TILES*N_COLS states explicitly.
    localparam
        S_IDLE = 2'd0,
        S_WAIT = 2'd1,
        S_RUN  = 2'd2;

    reg [1:0]                       state;
    reg [$clog2(N_COLS)-1:0]        step;    // 0..N_COLS-1 within tile
    reg [$clog2(N_TILES)-1:0]       tile;    // 0..N_TILES-1

    // ── step and tile counters ────────────────────────────────
    wire last_step = (step == N_COLS - 1);
    wire last_tile = (tile == N_TILES - 1);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state      <= S_IDLE;
            step       <= 0;
            tile       <= 0;
            rd_sel     <= 0;
            valid_ctrl <= 0;
            busy       <= 0;
        end else begin
            case (state)

                S_IDLE: begin
                    valid_ctrl <= 0;
                    busy       <= 0;
                    step       <= 0;
                    tile       <= 0;
                    rd_sel     <= 0;
                    if (start)
                        state <= S_WAIT;
                end

                // Wait for weight_mem_if to have data ready
                S_WAIT: begin
                    valid_ctrl <= 0;
                    busy       <= 1;
                    if (layer_ready)
                        state <= S_RUN;
                end

                S_RUN: begin
                    busy <= 1;

                    // ── valid_ctrl output ─────────────────────
                    if (step == 0) begin
                        // step 1: a_in_0 for all MACs in this row
                        // valid_ctrl[3*j +: 3] = 3'b001 for all j
                        begin : gen_load_ctrl
                            integer j;
                            for (j = 0; j < N_COLS; j = j + 1)
                                valid_ctrl[3*j +: 3] = 3'b001;
                        end
                    end else begin
                        // step 2..N_COLS: a_in_1 (ring shift) for all MACs
                        begin : gen_shift_ctrl
                            integer j;
                            for (j = 0; j < N_COLS; j = j + 1)
                                valid_ctrl[3*j +: 3] = 3'b010;
                        end
                    end

                    // ── advance counters ──────────────────────
                    if (last_step) begin
                        step <= 0;
                        if (last_tile) begin
                            // all tiles done for this layer
                            state      <= S_IDLE;
                            valid_ctrl <= 0;
                            busy       <= 0;
                        end else begin
                            tile   <= tile + 1;
                            rd_sel <= rd_sel + 1;
                        end
                    end else begin
                        step <= step + 1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
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



