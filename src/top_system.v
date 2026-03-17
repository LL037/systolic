// =============================================================
//  top_system_nn.v
//
//  Changes from previous version:
//    + layer2_base parameter added (passed to top_ctrl)
//    + layer_tile_number, layer_weight_base_addr wires added
//    + weight_base_addr mux:
//        MODE_LOAD  → tile_number * N        (L1)
//        MODE_LAYER → layer_weight_base_addr (L2)
//    + acc_sel mux:
//        MODE_LOAD  → tile_number            (L1 bank select)
//        MODE_LAYER → layer_tile_number      (L2 bank select)
//    + top_ctrl instance updated with new ports
// =============================================================
module top_system_nn #(
    parameter W           = 8,
    parameter ACC_W       = 16,
    parameter N           = 4,
    parameter N_MACS      = 4,
    parameter MEM_DEPTH   = 256,
    parameter layer2_base = 8'd32
)(
    input  wire                    clk,
    input  wire                    rst,
    input  wire                    start,
    input  wire                    clear_all,

    // Weight BRAM – port A
    output wire [7:0]              weight_bram_addr_a,
    output wire                    weight_bram_en_a,
    input  wire [15:0]             weight_bram_dout_a,

    // Weight BRAM – port B
    output wire [7:0]              weight_bram_addr_b,
    output wire                    weight_bram_en_b,
    input  wire [15:0]             weight_bram_dout_b,

    // Input BRAM
    output wire [7:0]              input_bram_addr,
    output wire                    input_bram_en,
    input  wire [15:0]             input_bram_dout,

    // Status
    output wire                    busy,
    output wire                    done,

    // Data outputs
    output wire signed [ACC_W-1:0] acc_out_0,
    output wire signed [ACC_W-1:0] acc_out_1,
    output wire signed [ACC_W-1:0] acc_out_2,
    output wire signed [ACC_W-1:0] acc_out_3,
    output wire [N_MACS-1:0]       valid_out
);

    // ── control signals ──────────────────────────────────────
    wire [2:0]  mode;
    wire        start_valid_pipeline;
    wire        start_weights;
    wire        start_layering;
    wire        start_input;

    // ── tile addressing ──────────────────────────────────────
    wire [2:0]  tile_number;
    wire [2:0]  layer_tile_number;
    wire [7:0]  layer_weight_base_addr;

    // ── weight_base_addr mux ─────────────────────────────────
    // MODE_LAYER=3'd2, MODE_LOAD=3'd1
    wire [7:0] weight_base_addr =
        (mode == 3'd2) ? layer_weight_base_addr
                       : (tile_number * N[7:0]);

    // ── acc_sel mux ──────────────────────────────────────────
    // L1: acc_sel = tile_number  (writes acc[0], acc[1] in MAC0/1)
    // L2: acc_sel = layer_tile_number[0]  (writes acc[0], acc[1] in MAC2/3)
    wire [2:0] acc_sel =
        (mode == 3'd2) ? {2'b0, layer_tile_number[0]}
                       : tile_number;

    // ── input base address ───────────────────────────────────
    wire [7:0] input_base_addr = 8'b00000001;

    // ── valid control ────────────────────────────────────────
    wire [11:0] valid_ctrl_pipeline;
    wire [11:0] valid_ctrl_layering;
    wire [11:0] valid_ctrl;
    assign valid_ctrl = valid_ctrl_pipeline | valid_ctrl_layering;

    // ── weight control ───────────────────────────────────────
    wire [N_MACS-1:0] weight_ctrl;
    wire [2:0]        load_weights;
    wire              weight_busy;

    // ── busy / ready ─────────────────────────────────────────
    wire valid_pipeline_busy;
    wire layering_busy;
    wire layer_ready;
    assign busy = valid_pipeline_busy | layering_busy;

    // ── data ─────────────────────────────────────────────────
    wire signed [ACC_W-1:0] a_in;
    wire signed [ACC_W-1:0] w_0, w_1, w_2, w_3;

    // ── memory interface valid flags ─────────────────────────
    wire input_if_valid;
    wire weight_if_valid;

    // ── prime signals ────────────────────────────────────────
    wire prime_input_en;
    wire prime_weight_en;

    // ── BRAM enables ─────────────────────────────────────────
    wire input_bram_en_raw;
    wire weight_bram_en_a_raw;
    wire weight_bram_en_b_raw;

    assign input_bram_en    = input_bram_en_raw    | prime_input_en;
    assign weight_bram_en_a = weight_bram_en_a_raw | prime_weight_en;
    assign weight_bram_en_b = weight_bram_en_b_raw | prime_weight_en;

    // ── clear ────────────────────────────────────────────────
    wire [N_MACS-1:0] clear;
    assign clear = {N_MACS{clear_all}};

    // ── rd_sel ───────────────────────────────────────────────
    wire rd_sel;

    // ─────────────────────────────────────────────────────────
    //  top_ctrl
    // ─────────────────────────────────────────────────────────
    top_ctrl #(
        .N           (N),
        .layer2_base (layer2_base)
    ) u_top_ctrl (
        .clk                    (clk),
        .rst                    (rst),
        .start                  (start),
        .valid_ctrl_busy        (valid_pipeline_busy),
        .layer_ctrl_busy        (layering_busy),
        .input_if_valid         (input_if_valid),
        .weight_if_valid        (weight_if_valid),
        .tile_number            (tile_number),
        .layer_tile_number      (layer_tile_number),
        .layer_weight_base_addr (layer_weight_base_addr),
        .mode                   (mode),
        .start_valid_pipeline   (start_valid_pipeline),
        .start_weights          (start_weights),
        .start_layering         (start_layering),
        .start_input            (start_input),
        .done                   (done),
        .prime_input_en         (prime_input_en),
        .prime_weight_en        (prime_weight_en)
    );

    // ─────────────────────────────────────────────────────────
    //  valid_pipeline_ctrl  (L1 load phase)
    // ─────────────────────────────────────────────────────────
    valid_pipeline_ctrl u_valid_pipeline_ctrl (
        .clk        (clk),
        .rst        (rst),
        .start      (start_valid_pipeline),
        .load_ready (weight_if_valid),
        .valid_ctrl (valid_ctrl_pipeline),
        .busy       (valid_pipeline_busy)
    );

    // ─────────────────────────────────────────────────────────
    //  layering_pipeline_ctrl  (L2 compute phase)
    // ─────────────────────────────────────────────────────────
    layering_pipeline_ctrl u_layering_pipeline_ctrl (
        .clk         (clk),
        .rst         (rst),
        .start       (start_layering),
        .layer_ready (layer_ready),
        .valid_ctrl  (valid_ctrl_layering),
        .rd_sel      (rd_sel),
        .busy        (layering_busy)
    );

    // ─────────────────────────────────────────────────────────
    //  weight_pipeline_ctrl
    // ─────────────────────────────────────────────────────────
    weight_pipeline_ctrl #(
        .N_MACS (N_MACS)
    ) u_weight_pipeline_ctrl (
        .clk         (clk),
        .rst         (rst),
        .start       (start_weights),
        .mode        (mode),
        .weight_ctrl (weight_ctrl),
        .load        (load_weights),
        .busy        (weight_busy),
        .load_ready  (),
        .layer_ready (layer_ready)
    );

    // ─────────────────────────────────────────────────────────
    //  weight_mem_if
    //
    //  L2 tile 0 (base = layer2_base = B):
    //    w2: B, B+2, B+4, B+6    → v11, v21, v31, v41
    //    w3: B+1, B+3, B+5, B+7  → v22, v12, v42, v32
    //
    //  L2 tile 1 (base = layer2_base + N = B'):
    //    w2: B', B'+2, B'+4, B'+6   → v13, v23, v33, v43
    //    w3: B'+1, B'+3, B'+5, B'+7 → v24, v14, v44, v34
    //
    //  ran flag resets when mode drops to IDLE in S_DECIDE_LAYER
    // ─────────────────────────────────────────────────────────
    weight_mem_if u_weight_mem_if (
        .clk              (clk),
        .rst              (rst),
        .weight_base_addr (weight_base_addr),
        .mode             (mode),
        .addr_a           (weight_bram_addr_a),
        .addr_b           (weight_bram_addr_b),
        .en_a             (weight_bram_en_a_raw),
        .en_b             (weight_bram_en_b_raw),
        .dout_a           (weight_bram_dout_a),
        .dout_b           (weight_bram_dout_b),
        .w0               (w_0),
        .w1               (w_1),
        .w2               (w_2),
        .w3               (w_3),
        .valid            (weight_if_valid),
        .done             ()
    );

    // ─────────────────────────────────────────────────────────
    //  input_mem_if
    // ─────────────────────────────────────────────────────────
    input_mem_if u_input_mem_if (
        .clk       (clk),
        .rst       (rst),
        .load_en   (start_input),
        .base_addr (input_base_addr),
        .bram_addr (input_bram_addr),
        .bram_en   (input_bram_en_raw),
        .bram_dout (input_bram_dout),
        .a_out     (a_in),
        .valid     (input_if_valid)
    );

    // ─────────────────────────────────────────────────────────
    //  mac_array
    // ─────────────────────────────────────────────────────────
    mac_array #(
        .W      (W),
        .ACC_W  (ACC_W),
        .N_MACS (N_MACS)
    ) u_mac_array (
        .clk             (clk),
        .rst             (rst),
        .valid_ctrl      (valid_ctrl),
        .valid_weight_in (weight_ctrl),
        .clear           (clear),
        .acc_sel         (acc_sel),
        .rd_sel          (rd_sel),
        .a_in            (a_in),
        .w_0             (w_0),
        .w_1             (w_1),
        .w_2             (w_2),
        .w_3             (w_3),
        .acc_out_0       (acc_out_0),
        .acc_out_1       (acc_out_1),
        .acc_out_2       (acc_out_2),
        .acc_out_3       (acc_out_3),
        .valid_out       (valid_out)
    );

endmodule