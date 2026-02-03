module top_pynq_z2 (
    input  wire       clk125,
    input  wire       btn_reset,
    input  wire       btn_start,
    input  wire       btn_clear,
    output wire [3:0] led,

    // AXI BRAM Controller BRAM_PORTA (weights)
    output wire       bram_clk_a,
    output wire       bram_rst_a,
    output wire       bram_en_a,
    output wire [7:0] bram_we_a,
    output wire [10:0] bram_addr_a,
    output wire [63:0] bram_wrdata_a,
    input  wire [63:0] bram_rddata_a,

    // AXI BRAM Controller BRAM_PORTB (inputs)
    output wire       bram_clk_b,
    output wire       bram_rst_b,
    output wire       bram_en_b,
    output wire [1:0] bram_we_b,
    output wire [8:0] bram_addr_b,
    output wire [15:0] bram_wrdata_b,
    input  wire [15:0] bram_rddata_b
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
        .weight_bram_en   (bram_en_a),
        .weight_bram_we   (bram_we_a),
        .weight_bram_addr (bram_addr_a),
        .weight_bram_din  (bram_wrdata_a),
        .weight_bram_dout (bram_rddata_a),
        .input_bram_en    (bram_en_b),
        .input_bram_we    (bram_we_b),
        .input_bram_addr  (bram_addr_b),
        .input_bram_din   (bram_wrdata_b),
        .input_bram_dout  (bram_rddata_b),
        .busy       (busy),
        .acc_out_0  (acc_out_0),
        .acc_out_1  (acc_out_1),
        .acc_out_2  (acc_out_2),
        .acc_out_3  (acc_out_3),
        .valid_out  (valid_out)
    );

    // LEDs: show busy + 3 valid bits (adjust mapping as needed)
    assign led = {busy, valid_out[2:0]};

    assign bram_clk_a = clk125;
    assign bram_clk_b = clk125;
    assign bram_rst_a = rst;
    assign bram_rst_b = rst;

endmodule
