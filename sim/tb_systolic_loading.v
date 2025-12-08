`timescale 1ns / 1ps

module tb_systolic_loading;

    parameter W      = 8;
    parameter ACC_W  = 16;
    parameter N_MACS = 4;
    parameter CLK_PERIOD = 10;

    reg clk;
    reg rst;
    reg start;
    reg signed [ACC_W-1:0] a_in;
    reg signed [ACC_W-1:0] w_0, w_1, w_2, w_3;

    reg [3:0] valid_in_1_dummy = 0;
    reg [3:0] valid_in_2_dummy = 0;
    reg [3:0] clear_dummy      = 0;

    wire [3:0] valid_ctrl;
    wire       busy;
    wire signed [ACC_W-1:0] acc_out_0, acc_out_1, acc_out_2, acc_out_3;
    wire [N_MACS-1:0] valid_out;

    reg signed [ACC_W-1:0] first_out_1;
    reg signed [ACC_W-1:0] second_out_1;
    reg signed [ACC_W-1:0] first_out_2;
    reg signed [ACC_W-1:0] second_out_2;

    // clock
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // FSM
    valid_pipeline_ctrl u_ctrl (
        .clk(clk),
        .rst(rst),
        .start(start),
        .valid_ctrl(valid_ctrl),
        .busy(busy)
    );

    // MAC array
    mac_array #(
        .W(W),
        .ACC_W(ACC_W),
        .N_MACS(N_MACS)
    ) u_array (
        .clk(clk),
        .rst(rst),
        .valid_in_0(valid_ctrl),
        .valid_in_1(valid_in_1_dummy),
        .valid_in_2(valid_in_2_dummy),
        .clear(clear_dummy),
        .a_in(a_in),
        .w_0(w_0), .w_1(w_1), .w_2(w_2), .w_3(w_3),
        .acc_out_0(acc_out_0),
        .acc_out_1(acc_out_1),
        .acc_out_2(acc_out_2),
        .acc_out_3(acc_out_3),
        .valid_out(valid_out)
    );

    initial begin
        rst = 1;
        start = 0;
        a_in = 0;
        w_0 = 2; w_1 = 3; w_2 = 0; w_3 = 0;

        #(CLK_PERIOD*3);
        rst = 0;

        // ---------- first input ----------
        a_in = 10;
        @(negedge clk) start = 1;
        @(negedge clk) start = 0;

        @(posedge valid_out[0]);
        first_out_1 = acc_out_0;
        @(posedge valid_out[1]);
        first_out_2 = acc_out_1;


        // ---------- second input ----------
        a_in = 5;
        @(negedge clk) start = 1;
        @(negedge clk) start = 0;

        @(posedge valid_out[0]);
        second_out_1 = acc_out_0;
        @(posedge valid_out[1]);
        second_out_2 = acc_out_1;   

        // ---------- output ----------
        $display("First : %0d", first_out_1);
        $display("Second: %0d", second_out_1);
        


        #(CLK_PERIOD*5);

        $display("First : %0d", first_out_2);
        $display("Second: %0d", second_out_2);
        $finish;

    end

endmodule
