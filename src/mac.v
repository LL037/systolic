module mac #(
    parameter W      = 8,
    parameter ACC_W  = 16,
    parameter NUM_ACC = 8
)(
    input  wire                    clk,
    input  wire                    rst,
    input  wire                    valid_in_0,
    input  wire                    valid_in_1,
    input  wire                    valid_in_2,
    input  wire                    clear,

    // 选哪个 accumulator（0~7）
    input  wire [2:0]              acc_sel,

    // 统一 ACC_W 宽度
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

    // 8 acc
    reg signed [ACC_W-1:0] acc [0:NUM_ACC-1];

    
    reg signed [ACC_W-1:0] mul_in;
    wire do_mac = valid_in_0 | valid_in_1 | valid_in_2;

    integer i;

    
    always @(*) begin
        mul_in = {ACC_W{1'b0}};
        if (valid_in_0)
            mul_in = a_in_0;
        else if (valid_in_1)
            mul_in = a_in_1;
        else if (valid_in_2)
            mul_in = a_in_2;
    end

    always @(posedge clk) begin
        // pass-through
        a_out_0 <= a_in_0;
        a_out_1 <= a_in_1;
        a_out_2 <= a_in_2;

        if (rst) begin
            for (i = 0; i < NUM_ACC; i = i + 1)
                acc[i] <= {ACC_W{1'b0}};
            acc_out   <= {ACC_W{1'b0}};
            valid_out <= 1'b0;
        end
        else begin
            if (clear) begin
                for (i = 0; i < NUM_ACC; i = i + 1)
                    acc[i] <= {ACC_W{1'b0}};
                acc_out   <= {ACC_W{1'b0}};
                valid_out <= 1'b0;
            end
            else begin
                valid_out <= 1'b0;

                if (do_mac) begin
                    acc[acc_sel] <= acc[acc_sel] + mul_in * weight;
                    acc_out      <= acc[acc_sel] + mul_in * weight;
                    valid_out    <= 1'b1;
                end
            end
        end
    end

endmodule
