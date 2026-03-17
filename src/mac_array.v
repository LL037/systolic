// =============================================================
//  mac_array.v  —  N_ROWS x N_COLS systolic MAC array
//
//  Row 0  : load mode — receives activations from BRAM (a_in_ext)
//  Row 1..N_ROWS-1 : layer compute — receives acc_rd_out from row above
//
//  valid_ctrl layout:
//    bits [3*N_COLS*(i+1)-1 : 3*N_COLS*i] = row i control
//    each row slice: bits [3*(j+1)-1 : 3*j] = MAC[i,j] {a2,a1,a0}
//
//  weight_valid_in / clear layout:
//    bits [N_COLS*(i+1)-1 : N_COLS*i] = row i
//
//  weight_in_flat layout:
//    bits [(i*N_COLS+j)*ACC_W +: ACC_W] = MAC[i,j] weight
// =============================================================
module mac_array #(
    parameter N_ROWS  = 2,
    parameter N_COLS  = 4,
    parameter W       = 8,
    parameter ACC_W   = 16,
    parameter NUM_ACC = 8
)(
    input  wire                                  clk,
    input  wire                                  rst,

    input  wire [3*N_COLS*N_ROWS-1:0]            valid_ctrl,
    input  wire [N_COLS*N_ROWS-1:0]              weight_valid_in,
    input  wire [N_COLS*N_ROWS-1:0]              clear,

    input  wire [2:0]                            acc_sel,
    input  wire [$clog2(NUM_ACC)-1:0]            rd_sel,

    input  wire signed [ACC_W-1:0]               a_in_ext,

    input  wire signed [ACC_W*N_COLS*N_ROWS-1:0] weight_in_flat,

    // last row outputs
    output wire signed [ACC_W*N_COLS-1:0]        acc_out_flat,
    output wire [N_COLS-1:0]                     valid_out,

    // all rows acc_out for readout
    output wire signed [ACC_W*N_COLS*N_ROWS-1:0] acc_all_flat
);

    // ── inter-row wires ───────────────────────────────────────
    // acc_rd_out_w[i][j] and acc_out_w[i][j]
    // Using 2D packed wires to avoid unpacked port issues
    wire signed [ACC_W-1:0] acc_rd_out_w [0:N_ROWS-1][0:N_COLS-1];
    wire signed [ACC_W-1:0] acc_out_w    [0:N_ROWS-1][0:N_COLS-1];
    wire        [N_COLS-1:0] valid_out_w  [0:N_ROWS-1];

    // ── generate rows ─────────────────────────────────────────
    genvar gi, gj;
    generate
        for (gi = 0; gi < N_ROWS; gi = gi + 1) begin : row_gen

            // ── a_in_0 mux: row 0 = a_in_ext, row i>0 = row above acc_rd_out
            wire signed [ACC_W-1:0] row_a_in_0 [0:N_COLS-1];
            for (gj = 0; gj < N_COLS; gj = gj + 1) begin : a_mux
                if (gi == 0)
                    assign row_a_in_0[gj] = a_in_ext;
                else
                    assign row_a_in_0[gj] = acc_rd_out_w[gi-1][gj];
            end

            // ── weight slice for this row
            wire signed [ACC_W-1:0] row_weight [0:N_COLS-1];
            for (gj = 0; gj < N_COLS; gj = gj + 1) begin : w_sl
                assign row_weight[gj] =
                    weight_in_flat[(gi*N_COLS+gj)*ACC_W +: ACC_W];
            end

            // ── mac_row instance
            mac_row #(
                .N_COLS  (N_COLS),
                .ACC_W   (ACC_W),
                .W       (W),
                .NUM_ACC (NUM_ACC)
            ) u_row (
                .clk             (clk),
                .rst             (rst),
                .valid_ctrl      (valid_ctrl[3*N_COLS*(gi+1)-1 : 3*N_COLS*gi]),
                .weight_valid_in (weight_valid_in[N_COLS*(gi+1)-1 : N_COLS*gi]),
                .clear           (clear[N_COLS*(gi+1)-1 : N_COLS*gi]),
                .acc_sel         (acc_sel),
                .rd_sel          (rd_sel),
                .a_in_0          (row_a_in_0),
                .weight_in       (row_weight),
                .acc_out         (acc_out_w[gi]),
                .acc_rd_out      (acc_rd_out_w[gi]),
                .valid_out       (valid_out_w[gi])
            );

            // ── pack all rows into acc_all_flat
            for (gj = 0; gj < N_COLS; gj = gj + 1) begin : pack_all
                assign acc_all_flat[(gi*N_COLS+gj)*ACC_W +: ACC_W] =
                    acc_out_w[gi][gj];
            end
        end
    endgenerate

    // ── last row → acc_out_flat and valid_out ─────────────────
    generate
        for (gj = 0; gj < N_COLS; gj = gj + 1) begin : last_row_out
            assign acc_out_flat[gj*ACC_W +: ACC_W] =
                acc_out_w[N_ROWS-1][gj];
        end
    endgenerate
    assign valid_out = valid_out_w[N_ROWS-1];

endmodule

// =============================================================
//  mac_row.v  —  one row of N_COLS MACs
//
//  Two operating modes:
//
//  MODE_LOAD (row 0 only):
//    Systolic skewed feed. Each MAC receives:
//      a_in_0 = external activation (skewed by column index,
//               handled externally via valid_ctrl timing)
//    Weights fed column by column via weight_in[j].
//
//  MODE_LAYER (row i > 0):
//    Ring-shift systolic. Each MAC receives:
//      step 1 : a_in_0[j] = acc_rd_out_prev[j]  (direct from row above)
//      step 2..N_COLS : a_in_1[j] = a_out[(j-1+N_COLS)%N_COLS]
//                                   (registered ring shift)
//    valid_ctrl drives which a_in is selected each step.
//
//  Inter-MAC connections (ring):
//    a_in_1[0]   = a_out_ring[N_COLS-1]   (wrap)
//    a_in_1[j>0] = a_out_ring[j-1]
//
//  acc_rd_out[j]: combinational read of acc[rd_sel] from MAC j
//                 feeds the row below as a_in_0.
// =============================================================
module mac_row #(
    parameter N_COLS  = 4,
    parameter ACC_W   = 16,
    parameter W       = 8,
    parameter NUM_ACC = 8
)(
    input  wire                              clk,
    input  wire                              rst,

    // Per-MAC valid control: {valid_ctrl[3*(N_COLS-1)+2 : 3*(N_COLS-1)], ..., valid_ctrl[2:0]}
    // Each 3-bit slice: [2]=a_in_2, [1]=a_in_1, [0]=a_in_0
    input  wire [3*N_COLS-1:0]              valid_ctrl,

    // Per-MAC weight valid
    input  wire [N_COLS-1:0]                weight_valid_in,

    // Per-MAC clear
    input  wire [N_COLS-1:0]                clear,

    // acc write bank select (same for all MACs in row)
    input  wire [2:0]                        acc_sel,

    // acc read bank select (for layer mode, selects h tile)
    input  wire [$clog2(NUM_ACC)-1:0]        rd_sel,

    // a_in_0 sources: from BRAM (row 0) or acc_rd_out of row above (row i>0)
    // N_COLS inputs, one per MAC
    input  wire signed [ACC_W-1:0]           a_in_0 [0:N_COLS-1],

    // Weight inputs: one per MAC
    input  wire signed [ACC_W-1:0]           weight_in [0:N_COLS-1],

    // Accumulator outputs (registered)
    output wire signed [ACC_W-1:0]           acc_out [0:N_COLS-1],

    // Combinational bank-read outputs (for row below's a_in_0)
    output wire signed [ACC_W-1:0]           acc_rd_out [0:N_COLS-1],

    // valid_out per MAC
    output wire [N_COLS-1:0]                 valid_out
);

    // ── ring shift wires ─────────────────────────────────────
    // a_out_ring[j] = MAC[j]'s registered pass-through of a_in_0
    // used as a_in_1 for MAC[(j+1)%N_COLS]
    wire signed [ACC_W-1:0] a_out_ring [0:N_COLS-1];

    // ── generate N_COLS MACs ──────────────────────────────────
    genvar j;
    generate
        for (j = 0; j < N_COLS; j = j + 1) begin : mac_col

            // ring: a_in_1[j] comes from a_out of MAC[(j-1+N_COLS)%N_COLS]
            wire signed [ACC_W-1:0] ring_in =
                (j == 0) ? a_out_ring[N_COLS-1] : a_out_ring[j-1];

            wire signed [ACC_W-1:0] acc_out_j;
            wire signed [ACC_W-1:0] acc_rd_out_j;
            wire                    valid_out_j;
            wire signed [ACC_W-1:0] a_out_0_j;  // registered a_in_0 → ring

            mac #(
                .W       (W),
                .ACC_W   (ACC_W),
                .NUM_ACC (NUM_ACC)
            ) u_mac (
                .clk             (clk),
                .rst             (rst),
                .acc_sel         (acc_sel),
                .rd_sel          ({{(3-$clog2(NUM_ACC)){1'b0}}, rd_sel}),
                .valid_ctrl      (valid_ctrl[3*j +: 3]),
                .weight_valid_in (weight_valid_in[j]),
                .clear           (clear[j]),
                .a_in_0          (a_in_0[j]),     // direct: BRAM or row-above acc_rd_out
                .a_in_1          (ring_in),        // ring shift from left neighbor
                .a_in_2          ({ACC_W{1'b0}}),  // unused
                .weight          (weight_in[j]),
                .acc_out         (acc_out_j),
                .acc_rd_out      (acc_rd_out_j),
                .valid_out       (valid_out_j),
                .a_out_0         (a_out_0_j),      // registered → feeds ring
                .a_out_1         (),
                .a_out_2         ()
            );

            assign a_out_ring[j]  = a_out_0_j;
            assign acc_out[j]     = acc_out_j;
            assign acc_rd_out[j]  = acc_rd_out_j;
            assign valid_out[j]   = valid_out_j;
        end
    endgenerate

endmodule