module top_system (
    input wire clk,
    input wire rst,
    input wire start_loading,
    input wire [7:0] data_in,
    input wire [7:0] w0, w1, w2, w3,
    // ... 其他端口
);

    // FSM 输出信号
    wire [3:0] fsm_valid_ctrl;
    wire       fsm_busy;

    // 实例化 FSM
    loading_fsm u_fsm (
        .clk        (clk),
        .rst        (rst),
        .start      (start_loading),
        .valid_ctrl (fsm_valid_ctrl), // FSM 产生的控制信号
        .busy       (fsm_busy)
    );

    // 实例化 MAC Array
    mac_array #(
        .W(8), .ACC_W(16), .N_MACS(4)
    ) u_mac_array (
        .clk        (clk),
        .rst        (rst),
        // 将 FSM 的输出连接到 valid_in_0
        .valid_in_0 (fsm_valid_ctrl), 
        
        .valid_in_1 (4'b0), // 暂时不用
        .valid_in_2 (4'b0), // 暂时不用
        .clear      (4'b0),
        .a_in       (data_in),
        .w_0(w0), .w_1(w1), .w_2(w2), .w_3(w3),
        // ... 输出连接
    );

endmodule