// =============================================================
//  mac_array.v  —  2x2 systolic MAC array
//  Changes from previous version:
//    + rd_sel input routed to MAC0 / MAC1
//    + MAC2 a_in_0 changed from acc_out_0 → acc_rd_out_0
//    + MAC3 a_in_0 changed from acc_out_1 → acc_rd_out_1
//    + MAC2 / MAC3 acc_sel now follows tile_number (was 3'b000)
//
//  Layering-mode data flow (4 steps per tile):
//    S_LOAD0: MAC2 a_in_0=h1(acc[0]), MAC3 a_in_0=h2(acc[0])  rd_sel=0
//    S_SWAP0: MAC2 a_in_1=h2(from MAC3), MAC3 a_in_1=h1(from MAC2) rd_sel=0
//    S_LOAD1: MAC2 a_in_0=h3(acc[1]), MAC3 a_in_0=h4(acc[1])  rd_sel=1
//    S_SWAP1: MAC2 a_in_1=h4(from MAC3), MAC3 a_in_1=h3(from MAC2) rd_sel=1
// =============================================================
module mac_array #(
    parameter W      = 8,
    parameter ACC_W  = 16,
    parameter N_MACS = 4
)(
    input  wire                    clk,
    input  wire                    rst,

    input  wire [3*N_MACS-1:0]     valid_ctrl,      // 12-bit: {ctrl3,ctrl2,ctrl1,ctrl0}
    input  wire [N_MACS-1:0]       clear,
    input  wire [N_MACS-1:0]       valid_weight_in,

    input  wire signed [ACC_W-1:0] a_in,            // external activation input

    // weight inputs
    input  wire signed [ACC_W-1:0] w_0,
    input  wire signed [ACC_W-1:0] w_1,
    input  wire signed [ACC_W-1:0] w_2,
    input  wire signed [ACC_W-1:0] w_3,

    input  wire [2:0]              acc_sel,          // tile_number → write bank
    input  wire                    rd_sel,           // ◀ NEW: 0=acc[0], 1=acc[1]

    // accumulator outputs
    output wire signed [ACC_W-1:0] acc_out_0,
    output wire signed [ACC_W-1:0] acc_out_1,
    output wire signed [ACC_W-1:0] acc_out_2,
    output wire signed [ACC_W-1:0] acc_out_3,
    output wire [N_MACS-1:0]       valid_out
);

    // ── valid_ctrl slice per MAC ──────────────────────────────
    wire [2:0] valid_ctrl_0 = valid_ctrl[2:0];
    wire [2:0] valid_ctrl_1 = valid_ctrl[5:3];
    wire [2:0] valid_ctrl_2 = valid_ctrl[8:6];
    wire [2:0] valid_ctrl_3 = valid_ctrl[11:9];

    // ── inter-MAC pass-through wires ─────────────────────────
    wire signed [ACC_W-1:0] a_out_0_1;    // MAC0 → MAC1 (a_out_0)
    wire signed [ACC_W-1:0] a_out_0_1_1;  // MAC0 → MAC1 (a_out_1)
    wire signed [ACC_W-1:0] a_out_1_0;    // MAC1 → MAC0 (a_out_2)
    wire signed [ACC_W-1:0] a_out_2_3;    // MAC2 → MAC3 (a_out_0, swap path)
    wire signed [ACC_W-1:0] a_out_3_2;    // MAC3 → MAC2 (a_out_0, swap path)

    // ── combinational bank-read outputs from MAC0/MAC1 ───────
    // These feed MAC2/MAC3 a_in_0 directly in layer mode.
    // acc_rd_out = acc[rd_sel], zero latency.
    wire signed [ACC_W-1:0] acc_rd_out_0;  // MAC0: h1(rd_sel=0) or h3(rd_sel=1)
    wire signed [ACC_W-1:0] acc_rd_out_1;  // MAC1: h2(rd_sel=0) or h4(rd_sel=1)

    // ── rd_sel zero-extended to 3 bits ───────────────────────
    wire [2:0] rd_sel_3 = {2'b00, rd_sel};

    // ─────────────────────────────────────────────────────────
    //  MAC 0  (top-left)
    //  load mode : a_in_0 = external activation
    //  layer mode: not active (valid_ctrl[2:0] = 0)
    // ─────────────────────────────────────────────────────────
    mac #(.W(W), .ACC_W(ACC_W)) mac_0 (
        .clk             (clk),
        .rst             (rst),
        .acc_sel         (acc_sel),
        .rd_sel          (rd_sel_3),        // ◀ selects h1 or h3
        .valid_ctrl      (valid_ctrl_0),
        .weight_valid_in (valid_weight_in[0]),
        .clear           (clear[0]),
        .a_in_0          (a_in),
        .a_in_1          (acc_out_2),
        .a_in_2          (a_out_1_0),
        .weight          (w_0),
        .acc_out         (acc_out_0),
        .acc_rd_out      (acc_rd_out_0),    // ◀ h1 or h3 → MAC2 a_in_0
        .valid_out       (valid_out[0]),
        .a_out_0         (a_out_0_1),
        .a_out_1         (a_out_0_1_1),
        .a_out_2         ()
    );

    // ─────────────────────────────────────────────────────────
    //  MAC 1  (top-right)
    //  load mode : a_in_0 = a_out_0_1 from MAC0
    //  layer mode: not active
    // ─────────────────────────────────────────────────────────
    mac #(.W(W), .ACC_W(ACC_W)) mac_1 (
        .clk             (clk),
        .rst             (rst),
        .acc_sel         (acc_sel),
        .rd_sel          (rd_sel_3),        // ◀ selects h2 or h4
        .valid_ctrl      (valid_ctrl_1),
        .weight_valid_in (valid_weight_in[1]),
        .clear           (clear[1]),
        .a_in_0          (a_out_0_1),
        .a_in_1          (a_out_0_1_1),
        .a_in_2          (acc_out_3),
        .weight          (w_1),
        .acc_out         (acc_out_1),
        .acc_rd_out      (acc_rd_out_1),    // ◀ h2 or h4 → MAC3 a_in_0
        .valid_out       (valid_out[1]),
        .a_out_0         (),
        .a_out_1         (),
        .a_out_2         (a_out_1_0)
    );

    // ─────────────────────────────────────────────────────────
    //  MAC 2  (bottom-left)  — layer-mode output accumulator
    //
    //  a_in_0 = acc_rd_out_0  (h1 or h3, direct feed)
    //  a_in_1 = a_out_3_2     (h2 or h4, swap from MAC3)
    //
    //  S_LOAD0/1 : valid_ctrl[8:6] = 3'b001  → uses a_in_0
    //  S_SWAP0/1 : valid_ctrl[8:6] = 3'b010  → uses a_in_1
    //
    //  acc_sel follows tile_number so each L2 output tile
    //  writes to a separate bank.
    // ─────────────────────────────────────────────────────────
    mac #(.W(W), .ACC_W(ACC_W)) mac_2 (
        .clk             (clk),
        .rst             (rst),
        .acc_sel         (acc_sel),         // ◀ was 3'b000, now tile_number
        .rd_sel          (3'b000),          // MAC2 read not used externally
        .valid_ctrl      (valid_ctrl_2),
        .weight_valid_in (valid_weight_in[2]),
        .clear           (clear[2]),
        .a_in_0          (acc_rd_out_0),    // ◀ was acc_out_0, now combinational
        .a_in_1          (a_out_3_2),       // swap path from MAC3
        .a_in_2          ({ACC_W{1'b0}}),
        .weight          (w_2),
        .acc_out         (acc_out_2),
        .acc_rd_out      (),
        .valid_out       (valid_out[2]),
        .a_out_0         (a_out_2_3),       // swap path to MAC3
        .a_out_1         (),
        .a_out_2         ()
    );

    // ─────────────────────────────────────────────────────────
    //  MAC 3  (bottom-right)  — layer-mode output accumulator
    //
    //  a_in_0 = acc_rd_out_1  (h2 or h4, direct feed)
    //  a_in_1 = a_out_2_3     (h1 or h3, swap from MAC2)
    //
    //  S_LOAD0/1 : valid_ctrl[11:9] = 3'b001  → uses a_in_0
    //  S_SWAP0/1 : valid_ctrl[11:9] = 3'b010  → uses a_in_1
    // ─────────────────────────────────────────────────────────
    mac #(.W(W), .ACC_W(ACC_W)) mac_3 (
        .clk             (clk),
        .rst             (rst),
        .acc_sel         (acc_sel),         // ◀ was 3'b000, now tile_number
        .rd_sel          (3'b000),
        .valid_ctrl      (valid_ctrl_3),
        .weight_valid_in (valid_weight_in[3]),
        .clear           (clear[3]),
        .a_in_0          (acc_rd_out_1),    // ◀ was acc_out_1, now combinational
        .a_in_1          (a_out_2_3),       // swap path from MAC2
        .a_in_2          ({ACC_W{1'b0}}),
        .weight          (w_3),
        .acc_out         (acc_out_3),
        .acc_rd_out      (),
        .valid_out       (valid_out[3]),
        .a_out_0         (a_out_3_2),       // swap path to MAC2
        .a_out_1         (),
        .a_out_2         ()
    );

endmodule