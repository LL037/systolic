// =============================================================
//  mac.v  —  single MAC unit with multi-bank accumulator
//  Changes from previous version:
//    + rd_sel  [2:0] input  : selects which acc bank to expose
//    + acc_rd_out     output : combinational read of acc[rd_sel]
//                             used by MAC2/MAC3 a_in_0 in layer mode
// =============================================================
module mac #(
    parameter W       = 8,
    parameter ACC_W   = 16,
    parameter NUM_ACC = 8
)(
    input  wire                    clk,
    input  wire                    rst,

    input  wire [2:0]              valid_ctrl,
    input  wire                    weight_valid_in,
    input  wire                    clear,
    input  wire [2:0]              acc_sel,     // write bank select
    input  wire [2:0]              rd_sel,      // ◀ NEW: read bank select

    input  wire signed [ACC_W-1:0] a_in_0,
    input  wire signed [ACC_W-1:0] a_in_1,
    input  wire signed [ACC_W-1:0] a_in_2,
    input  wire signed [ACC_W-1:0] weight,

    output reg  signed [ACC_W-1:0] acc_out,    // registered: last written bank
    output wire signed [ACC_W-1:0] acc_rd_out, // ◀ NEW: combinational read
    output reg                     valid_out,

    output reg  signed [ACC_W-1:0] a_out_0,
    output reg  signed [ACC_W-1:0] a_out_1,
    output reg  signed [ACC_W-1:0] a_out_2
);

    // ── internal wires ───────────────────────────────────────
    wire valid_in_0 = valid_ctrl[0];
    wire valid_in_1 = valid_ctrl[1];
    wire valid_in_2 = valid_ctrl[2];
    wire do_mac     = valid_in_0 | valid_in_1 | valid_in_2;

    // ── accumulator bank ─────────────────────────────────────
    reg signed [ACC_W-1:0] acc [0:NUM_ACC-1];

    // ◀ NEW: combinational read — zero latency, any bank
    assign acc_rd_out = acc[rd_sel];

    // ── input mux ────────────────────────────────────────────
    reg signed [ACC_W-1:0] mul_in;
    always @(*) begin
        mul_in = {ACC_W{1'b0}};
        if      (valid_in_0) mul_in = a_in_0;
        else if (valid_in_1) mul_in = a_in_1;
        else if (valid_in_2) mul_in = a_in_2;
    end

    reg signed [ACC_W-1:0] weight_in;
    always @(*) begin
        weight_in = {ACC_W{1'b0}};
        if (weight_valid_in) weight_in = weight;
    end

    // ── sequential logic ─────────────────────────────────────
    integer i;
    always @(posedge clk) begin
        // pass-through (registered 1-cycle delay)
        a_out_0 <= a_in_0;
        a_out_1 <= a_in_1;
        a_out_2 <= a_in_2;

        if (rst) begin
            for (i = 0; i < NUM_ACC; i = i + 1)
                acc[i] <= {ACC_W{1'b0}};
            acc_out   <= {ACC_W{1'b0}};
            valid_out <= 1'b0;
        end else begin
            if (clear) begin
                for (i = 0; i < NUM_ACC; i = i + 1)
                    acc[i] <= {ACC_W{1'b0}};
                acc_out   <= {ACC_W{1'b0}};
                valid_out <= 1'b0;
            end else begin
                valid_out <= 1'b0;
                if (do_mac) begin
                    acc[acc_sel] <= acc[acc_sel] + mul_in * weight_in;
                    acc_out      <= acc[acc_sel] + mul_in * weight_in;
                    valid_out    <= 1'b1;
                end
            end
        end
    end

endmodule