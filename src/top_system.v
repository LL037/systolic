module top_system #(
    parameter W      = 8,
    parameter ACC_W  = 16,
    parameter N_MACS = 4,
    parameter MEM_DEPTH = 256
)(
    input  wire                    clk,
    input  wire                    rst,
    
    input  wire                    start,

    // Clear signal
    input  wire                    clear_all,
    
    // ========================================
    // Weight BRAM Interface
    // ========================================
    output wire [$clog2(MEM_DEPTH)-1:0]  weight_bram_addr,
    output wire                          weight_bram_en,
    input  wire [N_MACS*ACC_W-1:0]       weight_bram_dout,  // 64-bit
    
    // ========================================
    // Input BRAM Interface
    // ========================================
    output wire [$clog2(MEM_DEPTH)-1:0]  input_bram_addr,
    output wire                          input_bram_en,
    input  wire [ACC_W-1:0]              input_bram_dout,   // 16-bit
    
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
    wire [$clog2(MEM_DEPTH)-1:0] w_addr;
    wire [$clog2(MEM_DEPTH)-1:0] in_addr;
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
        .start_weights          (start_weights),
        .start_layering         (start_layering),
        .start_input            (start_input)
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
    
    // Weight memory interface (with BRAM ports)
    weight_mem_if #(
        .N_MACS    (N_MACS),
        .DATA_W    (ACC_W),
        .MEM_DEPTH (MEM_DEPTH)
    ) u_weight_mem_if (
        .clk         (clk),
        .rst         (rst),
        .load        (load_weights),

        // BRAM interface - directly to top ports
        .bram_addr   (weight_bram_addr),
        .bram_en     (weight_bram_en),
        .bram_dout   (weight_bram_dout),

        .load_ready  (),
        .layer_ready (layer_ready),
        .w_addr      (w_addr),
        .w_0         (w_0),
        .w_1         (w_1),
        .w_2         (w_2),
        .w_3         (w_3)
    );


    // Input memory interface (with BRAM ports)
    input_mem_if #(
        .DATA_W    (ACC_W),
        .MEM_DEPTH (MEM_DEPTH)
    ) u_input_mem_if (
        .clk       (clk),
        .rst       (rst),
        .load_en   (start_input),

        // BRAM interface - directly to top ports
        .bram_addr (input_bram_addr),
        .bram_en   (input_bram_en),
        .bram_dout (input_bram_dout),

        .in_addr   (in_addr),
        .a_out     (a_in)
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