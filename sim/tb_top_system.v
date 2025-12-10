`timescale 1ns / 1ps

module tb_top_system;

    parameter W      = 8;
    parameter ACC_W  = 16;
    parameter N_MACS = 4;
    parameter CLK_PERIOD = 10;

    // DUT signals
    reg clk;
    reg rst;
    reg start;
    reg clear_all;
    reg start_valid_pipeline;
    reg start_layering;

    reg signed [ACC_W-1:0] a_in;
    reg signed [ACC_W-1:0] w_0, w_1, w_2, w_3;

    wire busy;
    wire signed [ACC_W-1:0] acc_out_0, acc_out_1, acc_out_2, acc_out_3;
    wire [N_MACS-1:0] valid_out;

    // Result storage
    reg signed [ACC_W-1:0] first_out_0, first_out_1;
    reg signed [ACC_W-1:0] second_out_0, second_out_1;
    reg signed [ACC_W-1:0] layer1_out_2, layer1_out_3;

    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // DUT instantiation
    top_system #(
        .W(W),
        .ACC_W(ACC_W),
        .N_MACS(N_MACS)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .start_valid_pipeline(start_valid_pipeline),
        .start_layering(start_layering),
        .a_in(a_in),
        .w_0(w_0), .w_1(w_1), .w_2(w_2), .w_3(w_3),
        .clear_all(clear_all),
        .busy(busy),
        .acc_out_0(acc_out_0),
        .acc_out_1(acc_out_1),
        .acc_out_2(acc_out_2),
        .acc_out_3(acc_out_3),
        .valid_out(valid_out)
    );

    initial begin
        // Initialize
        rst = 1;
        start = 0;
        start_valid_pipeline = 0;
        start_layering = 0;

        clear_all = 0;
        a_in = 0;
        w_0 = 2; w_1 = 3; w_2 = 5; w_3 = 7;

        #(CLK_PERIOD*3);
        rst = 0;

        // Trigger automatic loading -> layering sequence
        $display("=== Starting Operation (Loading then Layering) ===");
        a_in = 10;
        @(negedge clk) start = 1;start_valid_pipeline = 1;
        @(negedge clk) start = 0; start_valid_pipeline = 0;

        // Wait for first MAC outputs (loading phase)
        @(posedge valid_out[0]);
        first_out_0 = acc_out_0;
        @(posedge valid_out[1]);
        first_out_1 = acc_out_1;
        
        $display("Loading Phase - MAC0: %0d, MAC1: %0d", first_out_0, first_out_1);

        // Wait for layering phase outputs

        @(posedge clk) start = 1;start_layering = 1;
        @(posedge clk) start = 0; start_layering = 0;

        @(posedge valid_out[2]);
        layer1_out_2 = acc_out_2;
        @(posedge valid_out[3]);
        layer1_out_3 = acc_out_3;
                
        #(CLK_PERIOD*8);
        $display("Layering Phase - MAC2: %0d, MAC3: %0d", layer1_out_2, layer1_out_3);

        #(CLK_PERIOD*20);
        $display("=== Test Complete ===");
        $finish;
    end

    // Monitor
    initial begin
        $monitor("Time=%0t valid_out=%b acc=[%0d,%0d,%0d,%0d]", 
                 $time, valid_out, acc_out_0, acc_out_1, acc_out_2, acc_out_3);
    end

endmodule