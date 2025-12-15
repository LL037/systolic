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
    input wire start_weight,
    

    input wire [2:0]                mode,                     
    
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
    wire [11:0] valid_ctrl = valid_ctrl_pipeline | valid_ctrl_layering;
    wire [N_MACS-1:0] weight_ctrl;

    // busy wires
    wire weight_busy;
    wire valid_pipeline_busy;
    wire layering_busy;

    wire [N_MACS-1:0] clear;
    wire [N_MACS-1:0] valid_weight_in;

    // Mode control wires
    wire valid_pipeline_busy;
    wire layering_busy;
    
    // Data input wires
    wire signed [ACC_W-1:0] a_in;
    wire signed [ACC_W-1:0] w_0, w_1, w_2, w_3;
    wire [7:0] w_addr;
    wire [7:0] in_addr;
    wire [2:0] load_weights;
    wire load_input;
    wire weight_start;


    assign busy = weight_busy | valid_pipeline_busy | layering_busy;

    
    
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


    // Weight pipeline control
    weight_pipeline_ctrl #(
        .N_MACS (N_MACS)
    ) u_weight_pipeline_ctrl (
        //input
        .clk    (clk),
        .rst    (rst),
        .start  (start_weight),
        .mode   (mode),

        //output
        .weight_ctrl (weight_ctrl),
        .load   (load_weights),
        .busy   (weight_busy)
    );
    
    // Weight memory interface
    weight_mem_if #(
        .N_MACS  (N_MACS),
        .DATA_W (ACC_W),
        .MEM_DEPTH (256),
        .MEM_FILE ("weights.mem")
    ) u_weight_mem_if (
        .clk            (clk),
        .rst            (rst),
        .load_en        (load_weights),

        .w_addr         (w_addr),
        .w_0            (w_0),
        .w_1            (w_1),
        .w_2            (w_2),
        .w_3            (w_3),
    );


    // Input memory interface
    input_mem_if #(
        .DATA_WW       (W),
        .MEM_DEPTH   (256),
        .MEM_FILE    ("input.mem")
    ) u_input_mem_if (
        .clk        (clk),
        .rst        (rst),
        .load_en    (load_input),
        .in_addr    (in_addr),
        .a_out       (a_in)
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
        .valid_weight_in (valid_weight_in),
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