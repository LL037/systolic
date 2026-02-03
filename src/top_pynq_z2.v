module top_pynq_z2 (
    input  wire       clk125,
    input  wire       btn_reset,
    input  wire       btn_start,
    input  wire       btn_clear,
    output wire [3:0] led,

    // Weight BRAM port (connect to AXI BRAM Controller BRAM_PORTA)
    output wire       weight_bram_en,
    output wire [7:0] weight_bram_we,
    output wire [10:0] weight_bram_addr,
    output wire [63:0] weight_bram_din,
    input  wire [63:0] weight_bram_dout,

    // Input BRAM port (connect to AXI BRAM Controller BRAM_PORTB)
    output wire       input_bram_en,
    output wire [1:0] input_bram_we,
    output wire [8:0] input_bram_addr,
    output wire [15:0] input_bram_din,
    input  wire [15:0] input_bram_dout
);
    // Synchronize buttons to clk125
    reg [1:0] reset_sync;
    reg [1:0] start_sync;
    reg [1:0] clear_sync;

    always @(posedge clk125) begin
        reset_sync <= {reset_sync[0], btn_reset};
        start_sync <= {start_sync[0], btn_start};
        clear_sync <= {clear_sync[0], btn_clear};
    end

    wire rst = reset_sync[1];

    reg start_d;
    reg clear_d;

    always @(posedge clk125) begin
        start_d <= start_sync[1];
        clear_d <= clear_sync[1];
    end

    wire start_pulse = start_sync[1] & ~start_d;
    wire clear_pulse = clear_sync[1] & ~clear_d;

    wire busy;
    wire signed [15:0] acc_out_0;
    wire signed [15:0] acc_out_1;
    wire signed [15:0] acc_out_2;
    wire signed [15:0] acc_out_3;
    wire [3:0] valid_out;

    top_system #(
        .W      (8),
        .ACC_W  (16),
        .N_MACS (4)
    ) u_top_system (
        .clk        (clk125),
        .rst        (rst),
        .start      (start_pulse),
        .clear_all  (clear_pulse),
        .weight_bram_en   (weight_bram_en),
        .weight_bram_we   (weight_bram_we),
        .weight_bram_addr (weight_bram_addr),
        .weight_bram_din  (weight_bram_din),
        .weight_bram_dout (weight_bram_dout),
        .input_bram_en    (input_bram_en),
        .input_bram_we    (input_bram_we),
        .input_bram_addr  (input_bram_addr),
        .input_bram_din   (input_bram_din),
        .input_bram_dout  (input_bram_dout),
        .busy       (busy),
        .acc_out_0  (acc_out_0),
        .acc_out_1  (acc_out_1),
        .acc_out_2  (acc_out_2),
        .acc_out_3  (acc_out_3),
        .valid_out  (valid_out)
    );

    // LEDs: show busy + 3 valid bits (adjust mapping as needed)
    assign led = {busy, valid_out[2:0]};

endmodule
