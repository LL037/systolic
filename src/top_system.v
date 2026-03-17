// =============================================================
//  top_system_nn.v  —  generalized NxN MLP accelerator
//
//  N_COLS/2 weight_mem_if instances, one per MAC pair.
//  Each instance drives:
//    w_in[2k]   = w_out_a of instance k  (even MAC in pair)
//    w_in[2k+1] = w_out_b of instance k  (odd  MAC in pair)
//
//  BRAM port count: N_COLS ports total (N_COLS/2 port-A + N_COLS/2 port-B)
//  Each weight_mem_if instance gets its own addr/en/dout pair.
//
//  weight_base_addr for instance k:
//    MODE_LOAD  : weight_base_addr + k * N   (each pair reads a different column group)
//    MODE_LAYER : weight_base_addr + k * N*2 (stride-2 pairs, interleaved)
//    top_ctrl manages weight_base_addr for tile 0 of each segment;
//    instance offset is added here in top_system_nn.
// =============================================================
module top_system_nn #(
    parameter W       = 8,
    parameter ACC_W   = 16,
    parameter N       = 8,        // matrix dimension
    parameter N_COLS  = 4,        // MACs per row (must be even)
    parameter N_ROWS  = 2,        // number of layers
    parameter NUM_ACC = 8,        // acc banks per MAC (>= N/N_COLS)
    parameter MEM_DEPTH = 256,
    parameter [8*N_ROWS-1:0] LAYER_BASES = {8'd32, 8'd0}
)(
    input  wire                    clk,
    input  wire                    rst,
    input  wire                    start,
    input  wire                    clear_all,

    // Weight BRAM: N_COLS ports (N_COLS/2 instances × 2 ports each)
    // Packed flat: addr_a[k] = weight_bram_addr_a[8*(k+1)-1 : 8*k]
    output wire [8*(N_COLS/2)-1:0]     weight_bram_addr_a,
    output wire [(N_COLS/2)-1:0]       weight_bram_en_a,
    input  wire [ACC_W*(N_COLS/2)-1:0] weight_bram_dout_a,

    output wire [8*(N_COLS/2)-1:0]     weight_bram_addr_b,
    output wire [(N_COLS/2)-1:0]       weight_bram_en_b,
    input  wire [ACC_W*(N_COLS/2)-1:0] weight_bram_dout_b,

    // Input BRAM (single port, one activation per cycle)
    output wire [7:0]              input_bram_addr,
    output wire                    input_bram_en,
    input  wire [ACC_W-1:0]        input_bram_dout,

    // Status
    output wire                    busy,
    output wire                    done,

    // Final layer outputs: last row, N_COLS MACs
    output wire signed [ACC_W*N_COLS-1:0]          acc_out_flat,
    output wire [N_COLS-1:0]                        valid_out,

    // All rows debug output
    output wire signed [ACC_W*N_COLS*N_ROWS-1:0]   acc_all_flat
);

    localparam N_PAIRS = N_COLS / 2;   // weight_mem_if instance count
    localparam T       = N / N_COLS;   // tiles per layer

    // ── control signals ──────────────────────────────────────
    wire [2:0]                    mode;
    wire                          start_valid_pipeline;
    wire                          start_weights;
    wire                          start_layering;
    wire                          start_input;

    wire [$clog2(NUM_ACC)-1:0]    tile_number;
    wire [$clog2(NUM_ACC)-1:0]    layer_tile;
    wire [$clog2(N_ROWS)-1:0]     layer_idx;
    wire [7:0]                    weight_base_addr;   // base for pair 0
    wire [N_ROWS-1:0]             active_row;

    // ── acc_sel mux ──────────────────────────────────────────
    wire [2:0] acc_sel = (mode == 3'd2) ?
        {{(3-$clog2(NUM_ACC)){1'b0}}, layer_tile} :
        {{(3-$clog2(NUM_ACC)){1'b0}}, tile_number};

    // ── rd_sel from layering controller ─────────────────────
    wire [$clog2(NUM_ACC)-1:0] rd_sel;

    // ── valid_ctrl ───────────────────────────────────────────
    wire [3*N_COLS-1:0]          valid_ctrl_load;
    wire [3*N_COLS-1:0]          valid_ctrl_layer;
    wire [3*N_COLS*N_ROWS-1:0]   valid_ctrl;

    genvar gi;
    generate
        for (gi = 0; gi < N_ROWS; gi = gi + 1) begin : vc_mux
            assign valid_ctrl[3*N_COLS*(gi+1)-1 : 3*N_COLS*gi] =
                (gi == 0)           ? valid_ctrl_load  :
                (active_row[gi])    ? valid_ctrl_layer :
                                      {3*N_COLS{1'b0}};
        end
    endgenerate

    // ── weight_valid_in bus ───────────────────────────────────
    // weight_pipeline_ctrl outputs weight_ctrl [N_COLS-1:0]
    // (LOAD_MASK or LAYER_MASK, one bit per MAC in active row)
    wire [N_COLS-1:0]            weight_ctrl;
    wire [N_COLS*N_ROWS-1:0]     weight_valid_in_bus;

    generate
        for (gi = 0; gi < N_ROWS; gi = gi + 1) begin : wv_mux
            assign weight_valid_in_bus[N_COLS*(gi+1)-1 : N_COLS*gi] =
                (gi == 0 && mode == 3'd1)                    ? weight_ctrl :
                (gi > 0  && active_row[gi] && mode == 3'd2)  ? weight_ctrl :
                                                               {N_COLS{1'b0}};
        end
    endgenerate

    // ── weight_in_flat: route w_in to active row ─────────────
    wire signed [ACC_W-1:0]              w_in [0:N_COLS-1];
    wire signed [ACC_W*N_COLS*N_ROWS-1:0] weight_in_flat;

    genvar gj;
    generate
        for (gi = 0; gi < N_ROWS; gi = gi + 1) begin : wf_row
            for (gj = 0; gj < N_COLS; gj = gj + 1) begin : wf_col
                assign weight_in_flat[(gi*N_COLS+gj)*ACC_W +: ACC_W] =
                    (gi == 0 && mode == 3'd1)                    ? w_in[gj] :
                    (gi > 0  && active_row[gi] && mode == 3'd2)  ? w_in[gj] :
                                                                    {ACC_W{1'b0}};
            end
        end
    endgenerate

    // ── clear bus ────────────────────────────────────────────
    wire [N_COLS*N_ROWS-1:0] clear_bus =
        {(N_COLS*N_ROWS){clear_all}};

    // ── busy ─────────────────────────────────────────────────
    wire valid_pipeline_busy;
    wire layer_ctrl_busy;
    wire layer_ready;
    wire weight_busy;
    assign busy = valid_pipeline_busy | layer_ctrl_busy;

    // ── input mem ────────────────────────────────────────────
    wire input_if_valid;
    wire prime_input_en;
    wire prime_weight_en;
    wire input_bram_en_raw;
    wire signed [ACC_W-1:0] a_in;
    assign input_bram_en = input_bram_en_raw | prime_input_en;

    // ── weight_mem_if: N_PAIRS instances ─────────────────────
    // instance k handles MAC pair (2k, 2k+1)
    // base addr for instance k:
    //   MODE_LOAD  : weight_base_addr + k * N
    //   MODE_LAYER : weight_base_addr + k * N * 2
    // (weight_base_addr from top_ctrl is for pair 0, tile-relative)

    wire [7:0] wmif_base [0:N_PAIRS-1];
    wire       wmif_valid [0:N_PAIRS-1];
    wire       wmif_done  [0:N_PAIRS-1];

    wire weight_if_valid = wmif_valid[0]; // all instances sync, monitor pair 0

    genvar gk;
    generate
        for (gk = 0; gk < N_PAIRS; gk = gk + 1) begin : wmif_gen

            // per-instance BRAM wires
            wire [7:0]        inst_addr_a, inst_addr_b;
            wire              inst_en_a,   inst_en_b;
            wire [ACC_W-1:0]  inst_dout_a, inst_dout_b;
            wire [ACC_W-1:0]  inst_w_a,    inst_w_b;
            wire              inst_prime;

            // base address offset per instance
            assign wmif_base[gk] =
                (mode == 3'd2) ?
                    weight_base_addr + gk[7:0] * (N[7:0] * 8'd2) :
                    weight_base_addr + gk[7:0] * N[7:0];

            // prime: all instances primed together
            assign inst_prime = prime_weight_en;

            // BRAM port connections (flat bus slice)
            assign weight_bram_addr_a[8*(gk+1)-1 : 8*gk] = inst_addr_a;
            assign weight_bram_en_a[gk]                   = inst_en_a | inst_prime;
            assign inst_dout_a = weight_bram_dout_a[ACC_W*(gk+1)-1 : ACC_W*gk];

            assign weight_bram_addr_b[8*(gk+1)-1 : 8*gk] = inst_addr_b;
            assign weight_bram_en_b[gk]                   = inst_en_b | inst_prime;
            assign inst_dout_b = weight_bram_dout_b[ACC_W*(gk+1)-1 : ACC_W*gk];

            // weight_mem_if instance
            weight_mem_if #(
                .N        (N),
                .DATA_W   (ACC_W),
                .MEM_DEPTH(MEM_DEPTH)
            ) u_wmif (
                .clk              (clk),
                .rst              (rst),
                .weight_base_addr (wmif_base[gk]),
                .mode             (mode),
                .addr_a           (inst_addr_a),
                .addr_b           (inst_addr_b),
                .en_a             (inst_en_a),
                .en_b             (inst_en_b),
                .dout_a           (inst_dout_a),
                .dout_b           (inst_dout_b),
                .w_out_a          (inst_w_a),
                .w_out_b          (inst_w_b),
                .valid            (wmif_valid[gk]),
                .done             (wmif_done[gk])
            );

            // route to w_in array
            // instance k → w_in[2k] (even) and w_in[2k+1] (odd)
            assign w_in[2*gk]   = inst_w_a;
            assign w_in[2*gk+1] = inst_w_b;
        end
    endgenerate

    // ─────────────────────────────────────────────────────────
    //  top_ctrl
    // ─────────────────────────────────────────────────────────
    top_ctrl #(
        .N           (N),
        .N_COLS      (N_COLS),
        .N_ROWS      (N_ROWS),
        .NUM_ACC     (NUM_ACC),
        .LAYER_BASES (LAYER_BASES)
    ) u_top_ctrl (
        .clk                 (clk),
        .rst                 (rst),
        .start               (start),
        .valid_ctrl_busy     (valid_pipeline_busy),
        .layer_ctrl_busy     (layer_ctrl_busy),
        .input_if_valid      (input_if_valid),
        .weight_if_valid     (weight_if_valid),
        .tile_number         (tile_number),
        .layer_tile          (layer_tile),
        .layer_idx           (layer_idx),
        .weight_base_addr    (weight_base_addr),
        .active_row          (active_row),
        .mode                (mode),
        .start_valid_pipeline(start_valid_pipeline),
        .start_layering      (start_layering),
        .start_weights       (start_weights),
        .start_input         (start_input),
        .done                (done),
        .prime_input_en      (prime_input_en),
        .prime_weight_en     (prime_weight_en)
    );

    // ─────────────────────────────────────────────────────────
    //  valid_pipeline_ctrl  (row 0, L1 load)
    // ─────────────────────────────────────────────────────────
    valid_pipeline_ctrl #(
        .N (N_COLS)
    ) u_valid_pipeline_ctrl (
        .clk        (clk),
        .rst        (rst),
        .start      (start_valid_pipeline),
        .load_ready (weight_if_valid),
        .valid_ctrl (valid_ctrl_load),
        .busy       (valid_pipeline_busy)
    );

    // ─────────────────────────────────────────────────────────
    //  layering_pipeline_ctrl  (single instance, routes via active_row)
    // ─────────────────────────────────────────────────────────
    layering_pipeline_ctrl #(
        .N_COLS  (N_COLS),
        .N_TILES (T),
        .NUM_ACC (NUM_ACC)
    ) u_layering_ctrl (
        .clk         (clk),
        .rst         (rst),
        .start       (start_layering),
        .layer_ready (layer_ready),
        .valid_ctrl  (valid_ctrl_layer),
        .rd_sel      (rd_sel),
        .busy        (layer_ctrl_busy)
    );

    // ─────────────────────────────────────────────────────────
    //  weight_pipeline_ctrl
    // ─────────────────────────────────────────────────────────
    weight_pipeline_ctrl #(
        .N_MACS (N_COLS)
    ) u_weight_pipeline_ctrl (
        .clk         (clk),
        .rst         (rst),
        .start       (start_weights),
        .mode        (mode),
        .weight_ctrl (weight_ctrl),
        .load        (),
        .busy        (weight_busy),
        .load_ready  (),
        .layer_ready (layer_ready)
    );

    // ─────────────────────────────────────────────────────────
    //  input_mem_if
    // ─────────────────────────────────────────────────────────
    input_mem_if #(
        .N      (N_COLS),
        .DATA_W (ACC_W)
    ) u_input_mem_if (
        .clk       (clk),
        .rst       (rst),
        .load_en   (start_input),
        .base_addr (8'b00000001),
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
        .N_ROWS  (N_ROWS),
        .N_COLS  (N_COLS),
        .W       (W),
        .ACC_W   (ACC_W),
        .NUM_ACC (NUM_ACC)
    ) u_mac_array (
        .clk             (clk),
        .rst             (rst),
        .valid_ctrl      (valid_ctrl),
        .weight_valid_in (weight_valid_in_bus),
        .clear           (clear_bus),
        .acc_sel         (acc_sel),
        .rd_sel          (rd_sel),
        .a_in_ext        (a_in),
        .weight_in_flat  (weight_in_flat),
        .acc_out_flat    (acc_out_flat),
        .valid_out       (valid_out),
        .acc_all_flat    (acc_all_flat)
    );

endmodule