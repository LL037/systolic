module valid_pipeline_ctrl (
    input  wire       clk,
    input  wire       rst,
    input  wire       start,      // 新输入到达 -> 推入流水线
    output reg  [3:0] valid_ctrl, // valid 信号
    output reg        busy        // 阵列正在处理
);

    reg [3:0] valid_shift;

    always @(posedge clk) begin
        if (rst) begin
            valid_shift <= 4'b0000;
            busy        <= 1'b0;
        end else begin
            // 流水线推进：右移一格，新的 start 进入 MAC0
            valid_shift[0] <= start;
            valid_shift[1] <= valid_shift[0];

            // 只要 pipeline 里还有数据就维持 busy
            busy <= start | valid_shift[0] | valid_shift[1];
        end
    end

    always @(*) begin
        valid_ctrl = {2'b00, valid_shift[1], valid_shift[0]};
    end

endmodule
