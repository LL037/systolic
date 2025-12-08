module valid_pipeline_ctrl (
    input  wire       clk,
    input  wire       rst,
    input  wire       start,      // 新输入到达 -> 推入流水线
    output reg  [3:0] valid_ctrl, // valid 信号流经 MAC0~MAC3
    output reg        busy        // 阵列正在处理
);

    // valid_shift[0] → MAC0
    // valid_shift[1] → MAC1
    // valid_shift[2] → MAC2
    // valid_shift[3] → MAC3
    reg [3:0] valid_shift;

    always @(posedge clk) begin
        if (rst) begin
            valid_shift <= 4'b0000;
            busy        <= 1'b0;
        end else begin
            // 流水线推进：右移一格，新的 start 进入 MAC0
            valid_shift <= {valid_shift[2:0], start};

            // 只要 pipeline 里还有数据就维持 busy
            busy <= |valid_shift | start;
        end
    end

    always @(*) begin
        // valid 直连 MAC 阵列
        valid_ctrl = valid_shift;
    end

endmodule
