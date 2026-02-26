module top_system_nn #(
    parameter W      = 8,
    parameter ACC_W  = 16,
    parameter N_MACS = 4,
    parameter N      = 4,   // matrix dimension
    parameter MEM_DEPTH = 256
)(
    input  wire                    clk,
    input  wire                    rst,
    
    input  wire                    start,

    // Clear signal
    input  wire                    clear_all,
    
    output wire [$clog2(MEM_DEPTH)-1:0]  weight_bram_addr,
    output wire                          weight_bram_en,
    input  wire [N_MACS*ACC_W-1:0]       weight_bram_dout,  // 64-bit
    

    output wire [$clog2(MEM_DEPTH)-1:0]  input_bram_addr,
    output wire                          input_bram_en,
    input  wire [4*ACC_W-1:0]            input_bram_dout,   // 64-bit (BRAM_W fixed)
    
    // Status outputs
    output wire                    busy,
    output wire                    done,
    
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
    wire [N_MACS-1:0] weight_ctrl_raw;  // from weight_pipeline_ctrl
    // Route weight valid to correct MAC pair based on layer_sel_tile
    wire [N_MACS-1:0] weight_ctrl = layer_sel_tile ? 
                                    {2'b11, 2'b00} :   // layer2: mac2/mac3
                                    {2'b00, 2'b11};    // layer1: mac0/mac1

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

    // tile_ctrl → mem_if
    wire [$clog2(MEM_DEPTH)-1:0] weight_base_addr_tile;
    wire [$clog2(MEM_DEPTH)-1:0] input_base_addr_tile;
    wire                          layer_sel_tile;
    wire                          weight_mem_busy;


    assign busy = valid_pipeline_busy | layering_busy;

    // Top level control
    wire start_valid_pipeline;
    wire start_weights;
    wire start_layering;
    wire start_input;
    wire [2:0] mode;

    //tile control
    wire next_tile;
    wire next_tile_ready;
    wire [1:0] acc_sel_tile;  // $clog2(N_MACS)=2 bits
    wire load_tile_done;



    top_ctrl u_top_ctrl (
        .clk                    (clk),
        .rst                    (rst),
        .start                  (start),
        .valid_ctrl_busy        (valid_pipeline_busy),
        .layer_ctrl_busy        (layering_busy),
        .next_tile_ready        (next_tile_ready),
        .load_tile_done         (load_tile_done),

        .next_tile             (next_tile),
        .mode                   (mode),
        .start_valid_pipeline   (start_valid_pipeline),
        .start_weights          (start_weights),
        .start_layering         (start_layering),
        .start_input            (start_input),
        .done                   (done)
    );

    tile_ctrl u_tile_ctrl (
        .clk             (clk),
        .rst             (rst),
        .next_tile       (next_tile),
        .next_tile_ready (next_tile_ready),
        .load_tile_done  (load_tile_done),
        .weight_base_addr(weight_base_addr_tile),
        .input_base_addr (input_base_addr_tile),
        .acc_sel_tile    (acc_sel_tile),
        .layer_sel       (layer_sel_tile)
    );

    // Valid pipeline control
    valid_pipeline_ctrl #(.N(N)) u_valid_pipeline_ctrl (
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
        .weight_ctrl (weight_ctrl_raw),
        .load   (load_weights),
        .busy   (weight_busy),
        .load_ready (load_ready),
        .layer_ready ()
    );
    
    // Weight memory interface
    weight_mem_if #(
        .N          (N_MACS),
        .MACS_PER_ROW(N_MACS/2),
        .DATA_W     (ACC_W),
        .MEM_DEPTH  (MEM_DEPTH)
    ) u_weight_mem_if (
        .clk        (clk),
        .rst        (rst),
        .start      (start_weights),
        .base_addr  (weight_base_addr_tile),
        .layer_sel  (layer_sel_tile),
        .bram_addr  (weight_bram_addr),
        .bram_en    (weight_bram_en),
        .bram_dout  (weight_bram_dout),
        .w0         (w_0),
        .w1         (w_1),
        .w2         (w_2),
        .w3         (w_3),
        .busy       (weight_mem_busy),
        .load_ready (load_ready)
    );


    // Input memory interface
    input_mem_if #(
        .N         (N_MACS),
        .DATA_W    (ACC_W),
        .MEM_DEPTH (MEM_DEPTH)
    ) u_input_mem_if (
        .clk       (clk),
        .rst       (rst),
        .load_en   (valid_ctrl[0] | load_ready),  // pre-load on load_ready, then advance on valid
        .base_addr (input_base_addr_tile),
        .bram_addr (input_bram_addr),
        .bram_en   (input_bram_en),
        .bram_dout (input_bram_dout),
        .a_out     (a_in),
        .in_idx    ()
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

        .acc_sel    ({1'b0, acc_sel_tile}),
        
        // Outputs
        .acc_out_0  (acc_out_0),
        .acc_out_1  (acc_out_1),
        .acc_out_2  (acc_out_2),
        .acc_out_3  (acc_out_3),
        .valid_out  (valid_out)
    );

endmodule