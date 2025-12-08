module mac #(
    parameter W      = 8,
    parameter ACC_W  = 16
)(
    input  wire                    clk,
    input  wire                    rst,
    input  wire                    valid_in_0,
    input  wire                    valid_in_1,
    input  wire                    valid_in_2,
    input  wire                    clear,

    // unified to ACC_W width
    input  wire signed [ACC_W-1:0] a_in_0,
    input  wire signed [ACC_W-1:0] a_in_1,
    input  wire signed [ACC_W-1:0] a_in_2,
    input  wire signed [ACC_W-1:0] weight,

    output reg  signed [ACC_W-1:0] acc_out,
    output reg                     valid_out,

    output reg  signed [ACC_W-1:0] a_out_0,
    output reg  signed [ACC_W-1:0] a_out_1,
    output reg  signed [ACC_W-1:0] a_out_2
);

    always @(posedge clk) begin

        // pass-through
        a_out_0 <= a_in_0;
        a_out_1 <= a_in_1;
        a_out_2 <= a_in_2;

        if (rst) begin
            acc_out   <= 0;
            valid_out <= 0;
        end
        else begin
            if (clear) begin
                acc_out   <= 0;
                valid_out <= 0;
            end
            else if (valid_in_0) begin
                acc_out   <= acc_out + a_in_0 * weight;
                valid_out <= 1;
            end
            else if (valid_in_1) begin
                acc_out   <= acc_out + a_in_1 * weight;
                valid_out <= 1;
            end
            else if (valid_in_2) begin
                acc_out   <= acc_out + a_in_2 * weight;
                valid_out <= 1;
            end
            else begin
                valid_out <= 0;
            end
        end
    end
endmodule
