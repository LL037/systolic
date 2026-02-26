`timescale 1ns/1ps

// Testbench for top_system_nn
// BRAM is modeled as combinational (async ROM): addr is a registered output
// from weight_mem_if/input_mem_if, so data appears the same cycle addr changes.
//
// Weight BRAM layout (BRAM_W=64, DATA_W=16, N=4, MACS_PER_ROW=2):
//   BRAM_ROWS_PER_COL = N / (BRAM_W/DATA_W) = 4/4 = 1
//   TILE_BRAM_STRIDE  = MACS_PER_ROW * BRAM_ROWS_PER_COL = 2
//   NUM_TILES = N / MACS_PER_ROW = 2  (layer1: tile0,tile1)
//   LAYER2_W_OFFSET   = NUM_TILES * TILE_BRAM_STRIDE = 4
//   LAYER2_I_OFFSET   = ceil(N / (BRAM_W/DATA_W)) = 1
//
//   Addr 0: layer1, tile0, col0  → [w00, w10, w20, w30] packed LSB-first
//   Addr 1: layer1, tile0, col1  → [w01, w11, w21, w31]
//   Addr 2: layer1, tile1, col2  → [w02, w12, w22, w32]
//   Addr 3: layer1, tile1, col3  → [w03, w13, w23, w33]
//   Addr 4: layer2, tile0, col0  → [v00, v10, v20, v30]
//   Addr 5: layer2, tile0, col1  → [v01, v11, v21, v31]
//   Addr 6: layer2, tile1, col2  → [v02, v12, v22, v32]
//   Addr 7: layer2, tile1, col3  → [v03, v13, v23, v33]
//
// Input BRAM layout:
//   Addr 0: layer1 input [x0, x1, x2, x3] packed LSB-first
//   Addr 1: layer2 input [y0, y1, y2, y3]
//
// Test values:
//   Layer1 W1 = identity(4), input x = [1,2,3,4]  → expected y = [1,2,3,4]
//   Layer2 W2 = identity(4), input y = [1,2,3,4]  → expected z = [1,2,3,4]

module tb_top_nn;

    // ----------------------------------------------------------------
    //  Parameters
    // ----------------------------------------------------------------
    localparam W         = 8;
    localparam ACC_W     = 16;
    localparam N_MACS    = 4;
    localparam N         = 4;
    localparam MEM_DEPTH = 256;
    localparam BRAM_W    = 64;   // = 4 * ACC_W

    // ----------------------------------------------------------------
    //  Clock
    // ----------------------------------------------------------------
    reg clk = 0;
    always #5 clk = ~clk;

    // ----------------------------------------------------------------
    //  DUT signals
    // ----------------------------------------------------------------
    reg rst, start, clear_all;

    wire busy, done;
    wire signed [ACC_W-1:0] acc_out_0, acc_out_1, acc_out_2, acc_out_3;
    wire [N_MACS-1:0] valid_out;

    wire [7:0]           weight_bram_addr;   // $clog2(256)=8
    wire                 weight_bram_en;
    wire [BRAM_W-1:0]    weight_bram_dout;

    wire [7:0]           input_bram_addr;
    wire                 input_bram_en;
    wire [BRAM_W-1:0]    input_bram_dout;

    // ----------------------------------------------------------------
    //  BRAM models — combinational (async ROM)
    // ----------------------------------------------------------------
    reg [BRAM_W-1:0] weight_mem [0:MEM_DEPTH-1];
    reg [BRAM_W-1:0] input_mem  [0:MEM_DEPTH-1];

    assign weight_bram_dout = weight_mem[weight_bram_addr];
    assign input_bram_dout  = input_mem [input_bram_addr];

    // ----------------------------------------------------------------
    //  DUT
    // ----------------------------------------------------------------
    top_system_nn #(
        .W        (W),
        .ACC_W    (ACC_W),
        .N_MACS   (N_MACS),
        .N        (N),
        .MEM_DEPTH(MEM_DEPTH)
    ) dut (
        .clk             (clk),
        .rst             (rst),
        .start           (start),
        .clear_all       (clear_all),
        .weight_bram_addr(weight_bram_addr),
        .weight_bram_en  (weight_bram_en),
        .weight_bram_dout(weight_bram_dout),
        .input_bram_addr (input_bram_addr),
        .input_bram_en   (input_bram_en),
        .input_bram_dout (input_bram_dout),
        .busy            (busy),
        .done            (done),
        .acc_out_0       (acc_out_0),
        .acc_out_1       (acc_out_1),
        .acc_out_2       (acc_out_2),
        .acc_out_3       (acc_out_3),
        .valid_out       (valid_out)
    );

    // ----------------------------------------------------------------
    //  Waveform
    // ----------------------------------------------------------------
    initial begin
        $dumpfile("tb_top_nn.vcd");
        $dumpvars(0, tb_top_nn);
    end

    // ----------------------------------------------------------------
    //  BRAM init  (identity matrices, input = [1,2,3,4])
    // ----------------------------------------------------------------
    integer ii;
    initial begin
        for (ii = 0; ii < MEM_DEPTH; ii = ii + 1) begin
            weight_mem[ii] = 64'h0;
            input_mem[ii]  = 64'h0;
        end

        // Layer1 — W1 = identity(4)
        // word_k = bram_dout[k*16 +: 16]
        weight_mem[0] = {16'h0000, 16'h0000, 16'h0000, 16'h0001}; // col0=[1,0,0,0]
        weight_mem[1] = {16'h0000, 16'h0000, 16'h0001, 16'h0000}; // col1=[0,1,0,0]
        weight_mem[2] = {16'h0000, 16'h0001, 16'h0000, 16'h0000}; // col2=[0,0,1,0]
        weight_mem[3] = {16'h0001, 16'h0000, 16'h0000, 16'h0000}; // col3=[0,0,0,1]

        // Layer2 — W2 = identity(4)  (LAYER2_W_OFFSET=4)
        weight_mem[4] = {16'h0000, 16'h0000, 16'h0000, 16'h0001};
        weight_mem[5] = {16'h0000, 16'h0000, 16'h0001, 16'h0000};
        weight_mem[6] = {16'h0000, 16'h0001, 16'h0000, 16'h0000};
        weight_mem[7] = {16'h0001, 16'h0000, 16'h0000, 16'h0000};

        // Layer1 input: x = [1,2,3,4]  (BRAM addr 0)
        input_mem[0] = {16'd4, 16'd3, 16'd2, 16'd1};

        // Layer2 input: y = [1,2,3,4]  (LAYER2_I_OFFSET=1)
        input_mem[1] = {16'd4, 16'd3, 16'd2, 16'd1};
    end

    // ----------------------------------------------------------------
    //  Monitors
    // ----------------------------------------------------------------

    // Edge-detect busy / done
    reg busy_d, done_d;
    always @(posedge clk) begin
        busy_d <= busy;
        done_d <= done;
    end

    // top_ctrl state (hierarchical path)
    wire [3:0] top_state = dut.u_top_ctrl.state;

    // busy rise/fall
    always @(posedge clk) begin
        if ( busy && !busy_d) $display("[%0t] busy  ↑", $time);
        if (!busy &&  busy_d) $display("[%0t] busy  ↓", $time);
        if ( done && !done_d) $display("[%0t] DONE ← acc0=%0d  acc1=%0d  acc2=%0d  acc3=%0d",
                                        $time, acc_out_0, acc_out_1, acc_out_2, acc_out_3);
    end

    // valid_out pulses
    always @(posedge clk) begin
        if (|valid_out)
            $display("[%0t]   valid_out=%04b  acc0=%0d  acc1=%0d  acc2=%0d  acc3=%0d",
                     $time, valid_out, acc_out_0, acc_out_1, acc_out_2, acc_out_3);
    end

    // top_ctrl state changes
    reg [3:0] top_state_d;
    always @(posedge clk) begin
        top_state_d <= top_state;
        if (top_state !== top_state_d)
            $display("[%0t]   top_ctrl: state %0d → %0d", $time, top_state_d, top_state);
    end

    // weight_mem_if phase changes
    wire [2:0] w_phase = dut.u_weight_mem_if.phase;
    reg  [2:0] w_phase_d;
    always @(posedge clk) begin
        w_phase_d <= w_phase;
        if (w_phase !== w_phase_d)
            $display("[%0t]   weight_mem_if: phase %0d → %0d  addr=%0d",
                     $time, w_phase_d, w_phase, weight_bram_addr);
    end

    // load_ready / layer_ready pulses
    wire load_ready  = dut.u_weight_mem_if.load_ready;
    wire layer_ready = dut.u_weight_pipeline_ctrl.layer_ready;
    always @(posedge clk) begin
        if (load_ready)  $display("[%0t]   load_ready  ↑", $time);
        if (layer_ready) $display("[%0t]   layer_ready ↑", $time);
    end

    // ----------------------------------------------------------------
    //  Stimulus
    // ----------------------------------------------------------------
    initial begin
        rst = 1; start = 0; clear_all = 0;

        // Hold reset for 3 clock edges
        repeat(3) @(posedge clk);
        rst = 0;

        // Optional clear
        @(posedge clk); clear_all = 1;
        @(posedge clk); clear_all = 0;

        // Pulse start
        repeat(3) @(posedge clk);
        @(posedge clk);
        $display("[%0t] pulsing start", $time);
        start = 1;
        @(posedge clk); start = 0;

        // Wait for done or timeout
        repeat(300) @(posedge clk);
        $display("[%0t] TIMEOUT — done=%b busy=%b", $time, done, busy);
        $finish;
    end

endmodule
