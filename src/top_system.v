module top_system #(
    parameter W      = 8,
    parameter ACC_W  = 16,
    parameter N_MACS = 4
)(
    input  wire                    clk,
    input  wire                    rst,
    
    input  wire                    start,

    // Clear signal
    input  wire                    clear_all,

    // Weight BRAM port (to AXI BRAM Controller)
    output wire                    weight_bram_en,
    output wire [(N_MACS*ACC_W/8)-1:0] weight_bram_we,
    output wire [10:0]             weight_bram_addr,
    output wire [N_MACS*ACC_W-1:0] weight_bram_din,
    input  wire [N_MACS*ACC_W-1:0] weight_bram_dout,

    // Input BRAM port (to AXI BRAM Controller)
    output wire                    input_bram_en,
    output wire [(ACC_W/8)-1:0]    input_bram_we,
    output wire [8:0]              input_bram_addr,
    output wire [ACC_W-1:0]         input_bram_din,
    input  wire [ACC_W-1:0]         input_bram_dout,
    
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

    
    // Data input wires
    wire signed [ACC_W-1:0] a_in;
    wire signed [ACC_W-1:0] w_0, w_1, w_2, w_3;
    wire [7:0] w_addr;
    wire [7:0] in_addr;
    wire [2:0] load_weights;

    //ready signal
    wire load_ready;
    wire layer_ready;


    assign busy = valid_pipeline_busy | layering_busy;

    // Top level control
    wire start_valid_pipeline;
    wire start_weights;
    wire start_layering;
    wire start_input;
    wire [2:0] mode;


    top_ctrl u_top_ctrl (
        .clk                    (clk),
        .rst                    (rst),
        .start                  (start),
        .valid_ctrl_busy        (valid_pipeline_busy),
        .layer_ctrl_busy        (layering_busy),


        .mode                   (mode),
        .start_valid_pipeline   (start_valid_pipeline),
        .start_weights            (start_weights),
        .start_layering         (start_layering),
        .start_input             (start_input)
    );

    
    // Valid pipeline control
    valid_pipeline_ctrl u_valid_pipeline_ctrl (
        .clk        (clk),
        .rst        (rst),
        .start      (start_valid_pipeline),
        .load_ready (load_ready),
        .valid_ctrl (valid_ctrl_pipeline),
        .busy       (valid_pipeline_busy)
    );
    
    // Layering pipeline control
    layering_pipeline_ctrl u_layering_pipeline_ctrl (
        .clk        (clk),
        .rst        (rst),
        .start      (start_layering),
        .valid_ctrl (valid_ctrl_layering),
        .layer_ready (layer_ready),
        .busy       (layering_busy)
    );


    // Weight pipeline control
    weight_pipeline_ctrl #(
        .N_MACS (N_MACS)
    ) u_weight_pipeline_ctrl (
        //input
        .clk    (clk),
        .rst    (rst),
        .start  (start_weights),
        .mode   (mode),

        //output
        .weight_ctrl (weight_ctrl),
        .load   (load_weights),
        .busy   (weight_busy),
        .load_ready (load_ready),
        .layer_ready ()
    );
    
    // Weight memory interface
    weight_mem_if #(
        .N_MACS  (N_MACS),
        .DATA_W (ACC_W),
        .MEM_DEPTH (256),
        .MEM_FILE ("sim/weights.mem"),
        .USE_EXT_BRAM (1),
        .BRAM_ADDR_W (11)
        
    ) u_weight_mem_if (
        .clk            (clk),
        .rst            (rst),
        .load        (load_weights),
        .bram_en        (weight_bram_en),
        .bram_we        (weight_bram_we),
        .bram_addr      (weight_bram_addr),
        .bram_din       (weight_bram_din),
        .bram_dout      (weight_bram_dout),


        .load_ready     (),
        .layer_ready    (layer_ready),
        .w_addr         (w_addr),
        .w_0            (w_0),
        .w_1            (w_1),
        .w_2            (w_2),
        .w_3            (w_3)
    );


    // Input memory interface
    input_mem_if #(
        .DATA_W       (16),
        .MEM_DEPTH   (256),
        .MEM_FILE    ("sim/input.mem"),
        .USE_EXT_BRAM (1),
        .BRAM_ADDR_W (9)
    ) u_input_mem_if (
        .clk        (clk),
        .rst        (rst),
        .load_en    (start_input),
        .bram_en    (input_bram_en),
        .bram_we    (input_bram_we),
        .bram_addr  (input_bram_addr),
        .bram_din   (input_bram_din),
        .bram_dout  (input_bram_dout),

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
        .valid_weight_in (weight_ctrl),
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
