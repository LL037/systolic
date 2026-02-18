// mac_array_nn.v
// 2x2 physical MAC array that computes NxN matrix-vector product
// by time-multiplexing accumulator cells.
//
// Architecture (fixed 2x2 tiles):
//   Tile 1 (mac_0, mac_1): computes y[row_tile*2 + 0] and y[row_tile*2 + 1]
//   Tile 2 (mac_2, mac_3): computes y[row_tile*2 + 2] and y[row_tile*2 + 3]
//
// For NxN (N even):
//   - N/4 row_tile passes (each tile handles 2 rows per pass)
//   - acc_sel = row_tile index (0..N/4-1) within each tile
//   - Activation x[0..N-1] is fed sequentially via a_in
//   - weight_pipeline feeds w[row][col] column by column
//
// acc_sel width: 3 bits → max NUM_ACC=8 → max N=16 per tile pair (N<=16)
// For larger N, increase NUM_ACC and acc_sel width accordingly.

module mac_array_nn #(
    parameter W       = 8,
    parameter ACC_W   = 16,
    parameter N_MACS  = 4,               // Physical MACs (always 4 in this design)
    parameter NUM_ACC = 8                // Accumulator cells per MAC = N/2
)(
    input  wire                      clk,
    input  wire                      rst,

    // valid_ctrl: 3 bits per MAC, packed [3*N_MACS-1:0]
    input  wire [3*N_MACS-1:0]       valid_ctrl,

    // One clear bit per MAC
    input  wire [N_MACS-1:0]         clear,

    // One weight-valid bit per MAC
    input  wire [N_MACS-1:0]         valid_weight_in,

    // Single activation stream (systolic pass-through)
    input  wire signed [ACC_W-1:0]   a_in,

    // Separate weight per physical MAC (all 4 driven by weight_mem_if)
    input  wire signed [ACC_W-1:0]   w_0,
    input  wire signed [ACC_W-1:0]   w_1,
    input  wire signed [ACC_W-1:0]   w_2,
    input  wire signed [ACC_W-1:0]   w_3,

    // acc_sel per MAC (same index for all MACs in same tile during tiled computation)
    input  wire [2:0]                acc_sel_tile1,  // for mac_0, mac_1
    input  wire [2:0]                acc_sel_tile2,  // for mac_2, mac_3

    // Accumulator outputs
    output wire signed [ACC_W-1:0]   acc_out_0,
    output wire signed [ACC_W-1:0]   acc_out_1,
    output wire signed [ACC_W-1:0]   acc_out_2,
    output wire signed [ACC_W-1:0]   acc_out_3,
    output wire [N_MACS-1:0]         valid_out
);

    // Pass-through wires between MACs (horizontal chain within each tile row)
    wire signed [ACC_W-1:0] a_out_0_to_1_p0;   // mac_0 a_out_0 -> mac_1 a_in_0
    wire signed [ACC_W-1:0] a_out_0_to_1_p1;   // mac_0 a_out_1 -> mac_1 a_in_1

    wire signed [ACC_W-1:0] a_out_2_to_3_p0;   // mac_2 a_out_0 -> mac_3 a_in_0
    wire signed [ACC_W-1:0] a_out_2_to_3_p1;   // mac_2 a_out_1 -> mac_3 a_in_1

    // Vertical feedback wires (layer phase: acc_out feeds back as a_in_1/2)
    wire signed [ACC_W-1:0] a_out_1_to_0;      // mac_1 a_out_2 -> mac_0 a_in_2
    wire signed [ACC_W-1:0] a_out_3_to_2;      // mac_3 a_out_2 -> mac_2 a_in_2

    // Extract per-MAC valid_ctrl slices
    wire [2:0] vc0 = valid_ctrl[2:0];
    wire [2:0] vc1 = valid_ctrl[5:3];
    wire [2:0] vc2 = valid_ctrl[8:6];
    wire [2:0] vc3 = valid_ctrl[11:9];

    mac_nn #(.W(W), .ACC_W(ACC_W), .NUM_ACC(NUM_ACC)) mac_0 (
        .clk            (clk),
        .rst            (rst),
        .valid_ctrl     (vc0),
        .weight_valid_in(valid_weight_in[0]),
        .clear          (clear[0]),
        .acc_sel        (acc_sel_tile1),
        .a_in_0         (a_in),             // fresh activation input
        .a_in_1         (acc_out_2),        // layer phase: prev layer result
        .a_in_2         (a_out_1_to_0),     // layer phase: feedback from mac_1
        .weight         (w_0),
        .acc_out        (acc_out_0),
        .valid_out      (valid_out[0]),
        .a_out_0        (a_out_0_to_1_p0),
        .a_out_1        (a_out_0_to_1_p1),
        .a_out_2        ()
    );


    mac_nn #(.W(W), .ACC_W(ACC_W), .NUM_ACC(NUM_ACC)) mac_1 (
        .clk            (clk),
        .rst            (rst),
        .valid_ctrl     (vc1),
        .weight_valid_in(valid_weight_in[1]),
        .clear          (clear[1]),
        .acc_sel        (acc_sel_tile1),
        .a_in_0         (a_out_0_to_1_p0),  // activation from mac_0
        .a_in_1         (a_out_0_to_1_p1),
        .a_in_2         (acc_out_3),         // layer phase: prev layer result
        .weight         (w_1),
        .acc_out        (acc_out_1),
        .valid_out      (valid_out[1]),
        .a_out_0        (),
        .a_out_1        (),
        .a_out_2        (a_out_1_to_0)       // feedback to mac_0 a_in_2
    );


    mac_nn #(.W(W), .ACC_W(ACC_W), .NUM_ACC(NUM_ACC)) mac_2 (
        .clk            (clk),
        .rst            (rst),
        .valid_ctrl     (vc2),
        .weight_valid_in(valid_weight_in[2]),
        .clear          (clear[2]),
        .acc_sel        (acc_sel_tile2),
        .a_in_0         (acc_out_0),         // layer phase: tile1 result
        .a_in_1         (a_out_3_to_2),      // feedback from mac_3
        .a_in_2         ({ACC_W{1'b0}}),
        .weight         (w_2),
        .acc_out        (acc_out_2),
        .valid_out      (valid_out[2]),
        .a_out_0        (a_out_2_to_3_p0),
        .a_out_1        (),
        .a_out_2        ()
    );

    mac_nn #(.W(W), .ACC_W(ACC_W), .NUM_ACC(NUM_ACC)) mac_3 (
        .clk            (clk),
        .rst            (rst),
        .valid_ctrl     (vc3),
        .weight_valid_in(valid_weight_in[3]),
        .clear          (clear[3]),
        .acc_sel        (acc_sel_tile2),
        .a_in_0         (acc_out_1),         // layer phase: tile1 result
        .a_in_1         (a_out_2_to_3_p0),   // from mac_2
        .a_in_2         ({ACC_W{1'b0}}),
        .weight         (w_3),
        .acc_out        (acc_out_3),
        .valid_out      (valid_out[3]),
        .a_out_0        (a_out_3_to_2),      // feedback to mac_2
        .a_out_1        (),
        .a_out_2        ()
    );

endmodule