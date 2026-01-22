module top_pynq_z2 (
    input  wire       clk125,
    input  wire       btn_reset,
    input  wire       btn_start,
    input  wire       btn_clear,
    output wire [3:0] led
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
