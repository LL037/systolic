`timescale 1 ps / 1 ps

module tb_design_1_wrapper;

    // Inputs
    reg clk;
    reg rst;
    reg start;
    reg clear_all;

    // Outputs
    wire busy;
    wire [3:0] valid_out;

    // Instantiate the DUT
    design_1_wrapper uut (
        .busy(busy),
        .clear_all(clear_all),
        .clk(clk),
        .rst(rst),
        .start(start),
        .valid_out(valid_out)
    );

    // Clock generation: 10ns period (100MHz)
    initial clk = 0;
    always #5000 clk = ~clk; // 5000 ps = 5 ns half-period

    // Test sequence
    initial begin
        // Initialize
        rst       = 1;
        start     = 0;
        clear_all = 0;

        // Hold reset for a few cycles
        #50000;
        rst = 0;
        #20000;

        // Pulse start
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        // Wait for busy to assert then deassert
        wait (busy == 1);
        $display("[%0t] busy asserted", $time);

        wait (busy == 0);
        $display("[%0t] busy deasserted", $time);
        $display("[%0t] valid_out = %b", $time, valid_out);

        // Wait a few more cycles
        #100000;

        // Test clear_all
        @(posedge clk);
        clear_all = 1;
        @(posedge clk);
        clear_all = 0;
        #50000;

        // Second run
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        wait (busy == 1);
        wait (busy == 0);
        $display("[%0t] Second run done, valid_out = %b", $time, valid_out);

        #100000;
        $display("=== Simulation Complete ===");
        $finish;
    end

    // Timeout watchdog
    initial begin
        #10000000; // 10 us
        $display("ERROR: Simulation timed out!");
        $finish;
    end

    // Optional: waveform dump
    initial begin
        $dumpfile("tb_design_1_wrapper.vcd");
        $dumpvars(0, tb_design_1_wrapper);
    end

endmodule