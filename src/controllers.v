// =============================================================
//  top_ctrl.v
//
//  Changes from previous version:
//    + layer2_base parameter: base address for L2 weights
//    + layer_tile_number [2:0]: independent counter for L2 tiles
//    + layer_weight_base_addr output: feeds weight_mem_if in L2
//    + L2 tile loop: S_ISSUE_LAYER_TILE → S_WAIT_LAY_ON →
//                    S_WAIT_LAY_OFF → S_DECIDE_LAYER → ...
//
//  Full FSM flow:
//
//  RESET → S_PRIME → S_PRIME_DONE → S_IDLE
//
//  Layer 1 tile loop (tile_number 0..NUM_TILES-1):
//    S_IDLE → S_ISSUE_LOAD → S_WAIT_VALID_HIGH → S_WAIT_VALID_LOW
//          → S_DECIDE → (more tiles: back to S_ISSUE_LOAD)
//                     → (done: S_ISSUE_LAYER_TILE)
//
//  Layer 2 tile loop (layer_tile_number 0..NUM_TILES-1):
//    S_ISSUE_LAYER_TILE → S_WAIT_LAY_ON → S_WAIT_LAY_OFF
//          → S_DECIDE_LAYER → (more tiles: back to S_ISSUE_LAYER_TILE)
//                           → (done: S_DONE)
//
//  S_DONE → S_IDLE
//
//  weight_base_addr mux (in top_system_nn):
//    MODE_LOAD  → tile_number * N
//    MODE_LAYER → layer2_base + layer_tile_number * N
// =============================================================
module top_ctrl #(
    parameter N           = 4,
    parameter layer2_base = 8'd32   // default: L2 weights start at addr 32
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       start,

    input  wire       valid_ctrl_busy,
    input  wire       layer_ctrl_busy,
    input  wire       input_if_valid,
    input  wire       weight_if_valid,

    // Layer 1 tile addressing
    output reg  [2:0] tile_number,
    // Layer 2 tile addressing
    output reg  [2:0] layer_tile_number,        // ◀ NEW
    output reg  [7:0] layer_weight_base_addr,   // ◀ NEW: layer2_base + layer_tile*N

    output reg  [2:0] mode,
    output reg        start_valid_pipeline,
    output reg        start_layering,
    output reg        start_weights,
    output reg        start_input,
    output reg        done,

    output reg        prime_input_en,
    output reg        prime_weight_en
);

    // ── tile counts ──────────────────────────────────────────
    localparam NUM_TILES = N / 2;

    // ── mode encoding ────────────────────────────────────────
    localparam [2:0]
        MODE_IDLE  = 3'd0,
        MODE_LOAD  = 3'd1,
        MODE_LAYER = 3'd2;

    // ── state encoding ───────────────────────────────────────
    localparam [3:0]
        S_IDLE              = 4'd0,
        S_ISSUE_LOAD        = 4'd1,
        S_WAIT_VALID_HIGH   = 4'd2,
        S_WAIT_VALID_LOW    = 4'd3,
        S_DECIDE            = 4'd4,   // L1 tile decision
        S_ISSUE_LAYER_TILE  = 4'd5,   // ◀ NEW (was S_ISSUE_LAYER)
        S_WAIT_LAY_ON       = 4'd6,
        S_WAIT_LAY_OFF      = 4'd7,
        S_DECIDE_LAYER      = 4'd8,   // ◀ NEW: L2 tile decision
        S_DONE              = 4'd9,
        S_PRIME             = 4'd10,
        S_PRIME_DONE        = 4'd11;

    reg [3:0] state;

    // ── L1 tile helpers ──────────────────────────────────────
    wire [2:0] next_tile       = tile_number + 1'b1;
    wire       all_l1_done     = (next_tile >= NUM_TILES[2:0]);

    // ── L2 tile helpers ──────────────────────────────────────
    wire [2:0] next_layer_tile  = layer_tile_number + 1'b1;
    wire       all_l2_done      = (next_layer_tile >= NUM_TILES[2:0]);

    // ─────────────────────────────────────────────────────────
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state                  <= S_PRIME;
            mode                   <= MODE_IDLE;
            tile_number            <= 3'd0;
            layer_tile_number      <= 3'd0;
            layer_weight_base_addr <= layer2_base;
            start_valid_pipeline   <= 1'b0;
            start_layering         <= 1'b0;
            start_weights          <= 1'b0;
            start_input            <= 1'b0;
            done                   <= 1'b0;
            prime_input_en         <= 1'b0;
            prime_weight_en        <= 1'b0;
        end else begin
            // ── default: pulse outputs low ───────────────────
            start_valid_pipeline <= 1'b0;
            start_layering       <= 1'b0;
            start_weights        <= 1'b0;
            start_input          <= 1'b0;
            done                 <= 1'b0;
            prime_input_en       <= 1'b0;
            prime_weight_en      <= 1'b0;

            case (state)

                // ── BRAM priming (first run startup) ─────────
                S_PRIME: begin
                    mode                   <= MODE_IDLE;
                    prime_input_en         <= 1'b1;
                    prime_weight_en        <= 1'b1;
                    state                  <= S_PRIME_DONE;
                end

                S_PRIME_DONE: begin
                    mode  <= MODE_IDLE;
                    state <= S_IDLE;
                end

                // ── wait for start ───────────────────────────
                S_IDLE: begin
                    mode               <= MODE_IDLE;
                    tile_number        <= 3'd0;
                    layer_tile_number  <= 3'd0;
                    layer_weight_base_addr <= layer2_base;
                    if (start && !valid_ctrl_busy && !layer_ctrl_busy)
                        state <= S_ISSUE_LOAD;
                end

                // ── Layer 1: issue one tile load ─────────────
                S_ISSUE_LOAD: begin
                    mode                 <= MODE_LOAD;
                    start_weights        <= 1'b1;
                    start_input          <= 1'b1;
                    start_valid_pipeline <= 1'b1;
                    state                <= S_WAIT_VALID_HIGH;
                end

                // wait weight_mem_if to start outputting
                S_WAIT_VALID_HIGH: begin
                    mode <= MODE_LOAD;
                    if (weight_if_valid)
                        state <= S_WAIT_VALID_LOW;
                end

                // wait weight_mem_if to finish
                S_WAIT_VALID_LOW: begin
                    mode <= MODE_LOAD;
                    if (!weight_if_valid)
                        state <= S_DECIDE;
                end

                // ── Layer 1 tile decision ─────────────────────
                S_DECIDE: begin
                    mode <= MODE_IDLE;   // brief IDLE clears weight_mem_if ran flag
                    if (all_l1_done) begin
                        // all L1 tiles done → start L2 tile loop
                        layer_tile_number      <= 3'd0;
                        layer_weight_base_addr <= layer2_base;
                        state                  <= S_ISSUE_LAYER_TILE;
                    end else begin
                        tile_number <= next_tile;
                        state       <= S_ISSUE_LOAD;
                    end
                end

                // ── Layer 2: issue one tile compute ──────────
                S_ISSUE_LAYER_TILE: begin
                    mode           <= MODE_LAYER;
                    start_weights  <= 1'b1;   // triggers weight_mem_if MODE_LAYER
                    start_layering <= 1'b1;   // triggers layering_pipeline_ctrl
                    state          <= S_WAIT_LAY_ON;
                end

                // wait layering_ctrl to go busy
                S_WAIT_LAY_ON: begin
                    mode <= MODE_LAYER;
                    if (layer_ctrl_busy)
                        state <= S_WAIT_LAY_OFF;
                end

                // wait layering_ctrl to finish
                S_WAIT_LAY_OFF: begin
                    mode <= MODE_LAYER;
                    if (!layer_ctrl_busy)
                        state <= S_DECIDE_LAYER;
                end

                // ── Layer 2 tile decision ─────────────────────
                S_DECIDE_LAYER: begin
                    mode <= MODE_IDLE;   // drop to IDLE: clears weight_mem_if ran flag
                                         // so next L2 tile can re-trigger
                    if (all_l2_done) begin
                        state <= S_DONE;
                    end else begin
                        layer_tile_number      <= next_layer_tile;
                        layer_weight_base_addr <= layer2_base +
                                                  {5'b0, next_layer_tile} * N[7:0];
                        state                  <= S_ISSUE_LAYER_TILE;
                    end
                end

                // ── done ─────────────────────────────────────
                S_DONE: begin
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule

// =============================================================
//  layering_pipeline_ctrl.v
//
//  Controls layer-2 computation through 4 sequential steps:
//
//   Step     State    rd_sel  valid_ctrl[11:6]  MAC2 src   MAC3 src
//   ----     -----    ------  ----------------  --------   --------
//    1       S_LOAD0    0     001_001           h1(a_in_0) h2(a_in_0)
//    2       S_SWAP0    0     010_010           h2(a_in_1) h1(a_in_1)
//    3       S_LOAD1    1     001_001           h3(a_in_0) h4(a_in_0)
//    4       S_SWAP1    1     010_010           h4(a_in_1) h3(a_in_1)
//
//  weight_mem_if (MODE_LAYER) streams in parallel:
//    w2 : v11, v21, v31, v41   (addr_a: B, B+2, B+4, B+6)
//    w3 : v22, v12, v42, v32   (addr_b: B+1, B+3, B+5, B+7)
//
//  Final results:
//    MAC2 acc[tile] = h1·v11 + h2·v21 + h3·v31 + h4·v41 = out[2*tile]
//    MAC3 acc[tile] = h2·v22 + h1·v12 + h4·v42 + h3·v32 = out[2*tile+1]
// =============================================================
module layering_pipeline_ctrl (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire        layer_ready,    // from weight_pipeline_ctrl
    output reg  [11:0] valid_ctrl,     // to mac_array
    output reg         rd_sel,         // ◀ NEW: 0=read h1/h2, 1=read h3/h4
    output reg         busy
);

    // ── state encoding ───────────────────────────────────────
    localparam [2:0]
        IDLE    = 3'd0,
        S_WAIT  = 3'd1,   // wait for layer_ready before firing
        S_LOAD0 = 3'd2,   // step 1: h1→MAC2, h2→MAC3 (a_in_0)
        S_SWAP0 = 3'd3,   // step 2: h2→MAC2, h1→MAC3 (a_in_1, swap)
        S_LOAD1 = 3'd4,   // step 3: h3→MAC2, h4→MAC3 (a_in_0, rd_sel=1)
        S_SWAP1 = 3'd5;   // step 4: h4→MAC2, h3→MAC3 (a_in_1, swap)

    reg [2:0] state, next_state;

    // ── state register ───────────────────────────────────────
    always @(posedge clk) begin
        if (rst) state <= IDLE;
        else     state <= next_state;
    end

    // ── next-state logic ─────────────────────────────────────
    // S_WAIT gates on layer_ready; all compute states advance
    // unconditionally (one cycle each, weight stream is in sync).
    always @(*) begin
        next_state = state;
        case (state)
            IDLE:    next_state = start       ? S_WAIT  : IDLE;
            S_WAIT:  next_state = layer_ready ? S_LOAD0 : S_WAIT;
            S_LOAD0: next_state = S_SWAP0;
            S_SWAP0: next_state = S_LOAD1;
            S_LOAD1: next_state = S_SWAP1;
            S_SWAP1: next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    // ── combinational output ─────────────────────────────────
    //  valid_ctrl[11:9] = MAC3 control  {a_in_2, a_in_1, a_in_0}
    //  valid_ctrl[8:6]  = MAC2 control
    //  valid_ctrl[5:0]  = MAC1/MAC0 — not active in layer mode
    //
    //  001 → select a_in_0 (direct from acc_rd_out)
    //  010 → select a_in_1 (swap path from opposite MAC)
    always @(*) begin
        valid_ctrl = 12'b0;
        rd_sel     = 1'b0;
        case (state)
            S_LOAD0: begin
                //        MAC3      MAC2      MAC1      MAC0
                valid_ctrl = {3'b001, 3'b001, 3'b000, 3'b000};
                rd_sel     = 1'b0;   // read acc[0]: h1, h2
            end
            S_SWAP0: begin
                valid_ctrl = {3'b010, 3'b010, 3'b000, 3'b000};
                rd_sel     = 1'b0;   // swap uses a_out registered last cycle
            end
            S_LOAD1: begin
                valid_ctrl = {3'b001, 3'b001, 3'b000, 3'b000};
                rd_sel     = 1'b1;   // read acc[1]: h3, h4
            end
            S_SWAP1: begin
                valid_ctrl = {3'b010, 3'b010, 3'b000, 3'b000};
                rd_sel     = 1'b1;   // maintain rd_sel (swap path, not rd_sel dependent)
            end
            default: begin
                valid_ctrl = 12'b0;
                rd_sel     = 1'b0;
            end
        endcase
    end

    // ── busy ─────────────────────────────────────────────────
    always @(posedge clk) begin
        if (rst) busy <= 1'b0;
        else     busy <= (next_state != IDLE);
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



