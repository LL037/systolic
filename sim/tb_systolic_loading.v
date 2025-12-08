`timescale 1ns / 1ps

module tb_systolic_loading;


    parameter W = 8;
    parameter ACC_W = 16;
    parameter N_MACS = 4;
    
    // 时钟周期定义 (100MHz)
    parameter CLK_PERIOD = 10;


    reg clk;
    reg rst;

    // FSM 控制信号
    reg start;
    wire [3:0] fsm_valid_ctrl; // FSM 输出连接到 Array 的 valid_in_0
    wire fsm_busy;

    // MAC Array 数据信号
    reg signed [ACC_W-1:0] a_in;
    reg signed [ACC_W-1:0] w_0, w_1, w_2, w_3;
    
    // 没用到的控制信号 (全部置 0)
    reg [3:0] valid_in_1_dummy;
    reg [3:0] valid_in_2_dummy;
    reg [3:0] clear_dummy;

    // 输出观测信号
    wire signed [ACC_W-1:0] acc_out_0, acc_out_1, acc_out_2, acc_out_3;
    wire [N_MACS-1:0] valid_out;


    // 实例化 FSM
    loading_fsm u_fsm (
        .clk        (clk),
        .rst        (rst),
        .start      (start),
        .valid_ctrl (fsm_valid_ctrl),
        .busy       (fsm_busy)
    );

    // 实例化 MAC Array
    mac_array #(
        .W(W), 
        .ACC_W(ACC_W), 
        .N_MACS(N_MACS)
    ) u_mac_array (
        .clk        (clk),
        .rst        (rst),
        // FSM 控制第一组 valid 端口
        .valid_in_0 (fsm_valid_ctrl), 
        
        // 其他端口暂时闲置
        .valid_in_1 (valid_in_1_dummy), 
        .valid_in_2 (valid_in_2_dummy),
        .clear      (clear_dummy),
        
        .a_in       (a_in),
        
        // 权重设置
        .w_0(w_0), .w_1(w_1), .w_2(w_2), .w_3(w_3),
        
        // 输出监测
        .acc_out_0(acc_out_0), 
        .acc_out_1(acc_out_1), 
        .acc_out_2(acc_out_2), 
        .acc_out_3(acc_out_3),
        .valid_out(valid_out)
    );

    
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // ============================================================
    // 5. 测试流程 (Stimulus)
    // ============================================================
    initial begin
        // 1. 初始化 & 复位
        $display("=== Simulation Start ===");
        rst = 1;
        start = 0;
        a_in = 0;
        w_0 = 0; w_1 = 0; w_2 = 0; w_3 = 0;
        valid_in_1_dummy = 0;
        valid_in_2_dummy = 0;
        clear_dummy = 0;

        #(CLK_PERIOD * 3); // 等待几个周期
        rst = 0;           // 释放复位
        #(CLK_PERIOD * 2);

        // 2. 配置权重 (Config Phase)
        // MAC 0 权重 = 2, MAC 1 权重 = 3
        // 预期结果：MAC0 = Input * 2, MAC1 = Input * 3
        w_0 = 8'd2;
        w_1 = 8'd3;
        w_2 = 8'd4; // unused
        w_3 = 8'd5; // unused
        
        $display("Wait for Weights to settle...");
        #(CLK_PERIOD);

        // 3. 启动 Loading Phase (Input = 10)
        $display("=== Triggering Loading Phase ===");
        
        // 设置输入数据 a_in = 10
        a_in = 16'd10; 

        // 发送 Start 脉冲给 FSM
        @(negedge clk); 
        start = 1;
        @(negedge clk);
        start = 0;

        // 4. 观察输出
        // FSM 会在接下来的周期依次拉高 valid_in_0[0] 和 valid_in_0[1]
        
        wait(fsm_busy == 0); // 等待 FSM 忙完
        
        #(CLK_PERIOD * 5); 

        // 5. 打印结果检查
        $display("=== Results Check ===");
        $display("Input: %d", a_in);
        $display("MAC_0 Expected: 10 * 2 = 20. Actual: %d", acc_out_0);
        $display("MAC_1 Expected: 10 * 3 = 30. Actual: %d", acc_out_1);

        if (acc_out_0 == 20 && acc_out_1 == 30)
            $display("SUCCESS: Logic Correct!");
        else
            $display("FAILURE: Calculation Error.");

        $stop;
    end


endmodule