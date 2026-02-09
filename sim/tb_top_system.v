`timescale 1ns/1ps

module tb_top_system;

    // parameters
    localparam W      = 8;
    localparam ACC_W  = 16;
    localparam N_MACS = 4;

    // signals
    reg  clk;
    reg  rst;
    reg  start;
    reg  clear_all;

    wire busy;
    wire done;
    wire signed [ACC_W-1:0] acc_out_0;
    wire signed [ACC_W-1:0] acc_out_1;
    wire signed [ACC_W-1:0] acc_out_2;
    wire signed [ACC_W-1:0] acc_out_3;
    wire [N_MACS-1:0]       valid_out;

    // clock
    initial clk = 0;
    always #5 clk = ~clk;

    // DUT
    top_system #(
        .W      (W),
        .ACC_W  (ACC_W),
        .N_MACS (N_MACS)
    ) dut (
        .clk        (clk),
        .rst        (rst),
        .start      (start),
        .clear_all  (clear_all),
        .busy       (busy),
        .done       (done),
        .acc_out_0  (acc_out_0),
        .acc_out_1  (acc_out_1),
        .acc_out_2  (acc_out_2),
        .acc_out_3  (acc_out_3),
        .valid_out  (valid_out)
    );

    // waveform
    initial begin
        $dumpfile("tb_top_system.vcd");
        $dumpvars(0, tb_top_system);
    end

    // monitor done signal
    always @(posedge clk) begin
        if (done)
            $display("DONE asserted at time %0t", $time);
    end

    // stimulus
    initial begin
        rst       = 1;
        start     = 0;
        clear_all = 0;

        // reset
        #20;
        rst = 0;

        // optional clear
        #10;
        clear_all = 1;
        #10;
        clear_all = 0;

        // start once
        #20;
        start = 1;
        #10;
        start = 0;

        // let it run
        #1000;

        $finish;
    end

endmodule
