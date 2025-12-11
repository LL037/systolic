module top_system #(
    parameter W      = 8,
    parameter ACC_W  = 16,
    parameter N_MACS = 4
)(
    input  wire                    clk,
    input  wire                    rst,
    
    // Control inputs
    input  wire                    start,                 // Start overall operation

    input wire start_valid_pipeline,
    input wire start_layering,
    
    // Data inputs
    input  wire signed [ACC_W-1:0] a_in,                  // Activation input
    input  wire signed [ACC_W-1:0] w_0,                   // Weight for MAC 0
    input  wire signed [ACC_W-1:0] w_1,                   // Weight for MAC 1
    input  wire signed [ACC_W-1:0] w_2,                   // Weight for MAC 2
    input  wire signed [ACC_W-1:0] w_3,                   // Weight for MAC 3
    
    // Clear signal
    input  wire                    clear_all,
    
    // Status outputs
    output wire                    busy,
    
    // Data outputs
    output wire signed [ACC_W-1:0] acc_out_0,
    output wire signed [ACC_W-1:0] acc_out_1,
    output wire signed [ACC_W-1:0] acc_out_2,
    output wire signed [ACC_W-1:0] acc_out_3,
    output wire [N_MACS-1:0]       valid_out
);

    // Control wires
    wire [11:0] valid_ctrl_pipeline;
    wire [11:0] valid_ctrl_layering;
    wire [11:0] valid_ctrl = valid_ctrl_pipeline + valid_ctrl_layering;

    wire [N_MACS-1:0] clear;
    
    // Mode control wires
    wire valid_pipeline_busy;
    wire layering_busy;
    
    
    // Valid pipeline control
    valid_pipeline_ctrl u_valid_pipeline_ctrl (
        .clk        (clk),
        .rst        (rst),
        .start      (start_valid_pipeline),
        .valid_ctrl (valid_ctrl_pipeline),
        .busy       (valid_pipeline_busy)
    );
    
    // Layering pipeline control
    layering_pipeline_ctrl u_layering_pipeline_ctrl (
        .clk        (clk),
        .rst        (rst),
        .start      (start_layering),
        .valid_ctrl (valid_ctrl_layering),
        .busy       (layering_busy)
    );

    weight_mem_if #(
        .W       (W),
        .ACC_W   (ACC_W),
        .N_MACS  (N_MACS)
    ) u_weight_mem_if (
        .clk            (clk),
        .rst            (rst),
        .load_weights   (start),  // Assuming start signal triggers weight loading
        .w_0            (w_0),
        .w_1            (w_1),
        .w_2            (w_2),
        .w_3            (w_3),
        .valid_weight_out (valid_weight_in)
    );

    input_mem_if #(
        .W       (W),
        .ACC_W   (ACC_W)
    ) u_input_mem_if (
        .clk        (clk),
        .rst        (rst),
        .a_in       (a_in)
    );

    weight_pipeline_ctrl #(
        .N_MACS (N_MACS)
    ) u_weight_pipeline_ctrl (
        .clk    (clk),
        .rst    (rst),
        .start  (start),
        .mode   (layering_busy ? 3'd2 : (valid_pipeline_busy ? 3'd1 : 3'd0)),
        .weight_ctrl (),
        .busy   (busy)
    );
    
    
    assign clear = {N_MACS{clear_all}};
    
    // MAC array
    mac_array #(
        .W      (W),
        .ACC_W  (ACC_W),
        .N_MACS (N_MACS)
    ) u_mac_array (
        .clk        (clk),
        .rst        (rst),
        
        // Control signals
        .valid_ctrl (valid_ctrl),
        .clear      (clear),
        
        // Data inputs
        .a_in       (a_in),
        .w_0        (w_0),
        .w_1        (w_1),
        .w_2        (w_2),
        .w_3        (w_3),
        
        // Outputs
        .acc_out_0  (acc_out_0),
        .acc_out_1  (acc_out_1),
        .acc_out_2  (acc_out_2),
        .acc_out_3  (acc_out_3),
        .valid_out  (valid_out)
    );

endmodule