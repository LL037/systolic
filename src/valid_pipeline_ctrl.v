module valid_pipeline_ctrl (
    input  wire       clk,
    input  wire       rst,
    input  wire       start,
    output reg  [11:0] valid_ctrl, 
    output reg        busy        
);

    reg [5:0] valid_shift;

    always @(posedge clk) begin
        if (rst) begin
            valid_shift <= 6'b000000;
            busy        <= 1'b0;
        end else begin
            valid_shift[0] <= start;
            valid_shift[3] <= valid_shift[0];

            busy <= start | valid_shift[0] | valid_shift[3];
        end
    end

    always @(*) begin
        valid_ctrl = {3'b000,3'b000,2'b00, valid_shift[3],2'b00, valid_shift[0]};
    end

endmodule
 