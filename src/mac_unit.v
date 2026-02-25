// mac_nn.v
// Single MAC unit with NUM_ACC accumulator cells.
// For NxN matrix mult with fixed 2x2 physical array:
//   - acc_sel[ceil(log2(N/2))-1:0] selects which output row's partial sum to update
//   - mul_sel chooses which a_in_* port is active (for pass-through chain)
// Parameters:
//   W       - weight/activation data width
//   ACC_W   - accumulator width (should be >= 2*W)
//   NUM_ACC - number of accumulator cells = N/2 (one per output row per tile)
//             3-bit acc_sel supports up to 8 rows per tile

module mac_nn #(
    parameter W       = 8,
    parameter ACC_W   = 16,
    parameter NUM_ACC = 8          // = N/2, max 8 with 3-bit acc_sel
)(
    input  wire                      clk,
    input  wire                      rst,

    // valid_ctrl[2:0]: one-hot select for a_in_0/1/2 (activation mux)
    input  wire [2:0]                valid_ctrl,
    input  wire                      weight_valid_in,

    // Clear all accumulators (between independent computations)
    input  wire                      clear,

    // Which accumulator cell accumulates this cycle
    input  wire [2:0]                acc_sel,        // log2(NUM_ACC) effectively

    // Activation inputs (pass-through chain)
    input  wire signed [ACC_W-1:0]   a_in_0,
    input  wire signed [ACC_W-1:0]   a_in_1,
    input  wire signed [ACC_W-1:0]   a_in_2,

    // Weight input
    input  wire signed [ACC_W-1:0]   weight,

    // Outputs
    output reg  signed [ACC_W-1:0]   acc_out,
    output reg                       valid_out,

    // Pass-through activations to next MAC in chain
    output reg  signed [ACC_W-1:0]   a_out_0,
    output reg  signed [ACC_W-1:0]   a_out_1,
    output reg  signed [ACC_W-1:0]   a_out_2
);

    wire valid_in_0 = valid_ctrl[0];
    wire valid_in_1 = valid_ctrl[1];
    wire valid_in_2 = valid_ctrl[2];

    // Accumulator bank
    reg signed [ACC_W-1:0] acc [0:NUM_ACC-1];

    reg signed [ACC_W-1:0] mul_in;
    reg signed [ACC_W-1:0] weight_in;
    wire do_mac = valid_in_0 | valid_in_1 | valid_in_2;

    integer i;

    // Activation mux (combinational)
    always @(*) begin
        mul_in = {ACC_W{1'b0}};
        if      (valid_in_0) mul_in = a_in_0;
        else if (valid_in_1) mul_in = a_in_1;
        else if (valid_in_2) mul_in = a_in_2;
    end

    // Weight gate (combinational)
    always @(*) begin
        weight_in = {ACC_W{1'b0}};
        if (weight_valid_in) weight_in = weight;
    end

    // Sequential: accumulate + pass-through
    always @(posedge clk) begin
        // Activation pass-through (1-cycle delay for pipeline alignment)
        a_out_0 <= a_in_0;
        a_out_1 <= a_in_1;
        a_out_2 <= a_in_2;

        if (rst) begin
            for (i = 0; i < NUM_ACC; i = i + 1)
                acc[i] <= {ACC_W{1'b0}};
            acc_out   <= {ACC_W{1'b0}};
            valid_out <= 1'b0;
        end else if (clear) begin
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

endmodule