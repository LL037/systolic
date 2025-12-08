module valid_pipeline_ctrl (
    input  wire       clk,
    input  wire       rst,
    input  wire       loading_start,
    output reg  [3:0] valid_ctrl, 
    output reg        busy        
);

    reg [3:0] valid_shift;

    always @(posedge clk) begin
        if (rst) begin
            valid_shift <= 4'b0000;
            busy        <= 1'b0;
        end else begin
            valid_shift[0] <= loading_start;
            valid_shift[1] <= valid_shift[0];

            busy <= loading_start | valid_shift[0] | valid_shift[1];
        end
    end

    always @(*) begin
        valid_ctrl = {2'b00, valid_shift[1], valid_shift[0]};
    end

endmodule
 