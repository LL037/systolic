`timescale 1ns / 1ps

module tb_top_system;

    parameter W      = 8;
    parameter ACC_W  = 16;
    parameter N_MACS = 4;
    parameter CLK_PERIOD = 10;

    // DUT signals
    reg clk;
    reg rst;
    reg start_valid_pipeline;
    reg start_layering;
    reg start_weight;
    reg [2:0] mode;
    reg clear_all;

    wire busy;
    wire signed [ACC_W-1:0] acc_out_0, acc_out_1, acc_out_2, acc_out_3;
    wire [N_MACS-1:0] valid_out;

    // Result storage
    reg signed [ACC_W-1:0] captured_out_0, captured_out_1;
    reg signed [ACC_W-1:0] captured_out_2, captured_out_3;

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
        
        // Start signals
        .start_valid_pipeline(start_valid_pipeline),
        .start_layering(start_layering),
        .start_weight(start_weight),
        
        // Mode
        .mode(mode),
        
        // Clear
        .clear_all(clear_all),
        
        // Status
        .busy(busy),
        
        // Outputs
        .acc_out_0(acc_out_0),
        .acc_out_1(acc_out_1),
        .acc_out_2(acc_out_2),
        .acc_out_3(acc_out_3),
        .valid_out(valid_out)
    );

    // Main test sequence
    initial begin
        // Initialize all inputs
        rst = 1;
        start_valid_pipeline = 0;
        start_layering = 0;
        start_weight = 0;
        mode = 3'b000;
        clear_all = 0;

        // Hold reset for a few cycles
        #(CLK_PERIOD * 3);
        rst = 0;
        #(CLK_PERIOD);

        // =============================================
        // Test 1: Weight Loading Phase
        // =============================================
        $display("\n=== Test 1: Weight Loading ===");
        $display("Time=%0t Starting weight load", $time);
        
        @(negedge clk);
        start_weight = 1;
        mode = 3'b001;  // Set mode as needed
        @(negedge clk);
        start_weight = 0;
        
        // Wait for weight loading to complete
        wait(busy == 1);
        $display("Time=%0t Weight controller busy", $time);
        wait(busy == 0);
        $display("Time=%0t Weight loading complete", $time);
        
        #(CLK_PERIOD * 2);

        // =============================================
        // Test 2: Valid Pipeline Operation
        // =============================================
        $display("\n=== Test 2: Valid Pipeline ===");
        $display("Time=%0t Starting valid pipeline", $time);
        
        @(negedge clk);
        start_valid_pipeline = 1;
        @(negedge clk);
        start_valid_pipeline = 0;

        // Wait for first MAC outputs
        fork
            begin
                @(posedge valid_out[0]);
                captured_out_0 = acc_out_0;
                $display("Time=%0t MAC0 valid: %0d", $time, captured_out_0);
            end
            begin
                @(posedge valid_out[1]);
                captured_out_1 = acc_out_1;
                $display("Time=%0t MAC1 valid: %0d", $time, captured_out_1);
            end
        join

        // Wait for pipeline to finish
        wait(busy == 0);
        $display("Time=%0t Valid pipeline complete", $time);
        
        #(CLK_PERIOD * 2);

        // =============================================
        // Test 3: Layering Pipeline Operation
        // =============================================
        $display("\n=== Test 3: Layering Pipeline ===");
        $display("Time=%0t Starting layering pipeline", $time);
        
        @(negedge clk);
        start_layering = 1;
        @(negedge clk);
        start_layering = 0;

        // Wait for layer outputs
        fork
            begin
                @(posedge valid_out[2]);
                captured_out_2 = acc_out_2;
                $display("Time=%0t MAC2 valid: %0d", $time, captured_out_2);
            end
            begin
                @(posedge valid_out[3]);
                captured_out_3 = acc_out_3;
                $display("Time=%0t MAC3 valid: %0d", $time, captured_out_3);
            end
        join

        wait(busy == 0);
        $display("Time=%0t Layering complete", $time);

        #(CLK_PERIOD * 5);

        // =============================================
        // Test 4: Clear and Re-run
        // =============================================
        $display("\n=== Test 4: Clear All ===");
        
        @(negedge clk);
        clear_all = 1;
        @(negedge clk);
        clear_all = 0;
        
        $display("Time=%0t Accumulators cleared", $time);
        $display("After clear: acc=[%0d, %0d, %0d, %0d]", 
                 acc_out_0, acc_out_1, acc_out_2, acc_out_3);

        #(CLK_PERIOD * 10);

        // =============================================
        // Summary
        // =============================================
        $display("\n=== Test Complete ===");
        $display("Final outputs: MAC0=%0d, MAC1=%0d, MAC2=%0d, MAC3=%0d",
                 acc_out_0, acc_out_1, acc_out_2, acc_out_3);
        
        $finish;
    end

    // Continuous monitor
    initial begin
        $monitor("Time=%0t | busy=%b valid=%b | acc=[%0d, %0d, %0d, %0d]", 
                 $time, busy, valid_out, 
                 acc_out_0, acc_out_1, acc_out_2, acc_out_3);
    end

    // Timeout watchdog
    initial begin
        #(CLK_PERIOD * 500);
        $display("ERROR: Test timeout!");
        $finish;
    end

endmodule