module top_system_nn #(
    parameter W      = 8,
    parameter ACC_W  = 16,
    parameter N = 4,
    parameter N_MACS = 4,
    parameter MEM_DEPTH = 256
)(
    input  wire                    clk,
    input  wire                    rst,
    
    input  wire                    start,

    // Clear signal
    input  wire                    clear_all,
    

   // Weight BRAM - port A
    output wire [7:0]  weight_bram_addr_a,
    output wire                          weight_bram_en_a,
    input  wire [15:0]              weight_bram_dout_a, // 16-bit 

    // Weight BRAM - port B  
    output wire [7:0]  weight_bram_addr_b,  
    output wire                          weight_bram_en_b,
    input  wire [15:0]              weight_bram_dout_b, // 16-bit 

    output wire [7:0]  input_bram_addr,
    output wire        input_bram_en,
    input  wire [15:0]  input_bram_dout,   // 16-bit
    
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

  // ── control ──────────────────────────────────────────────────
    wire                           next_tile;
    wire                           next_tile_ready;
    wire                           load_tile_done;
    wire [2:0]                     mode;

    wire                           start_valid_pipeline;
    wire                           start_weights;
    wire                           start_layering;
    wire                           start_input;

    // ── tile ctrl ────────────────────────────────────────────────
    wire [7:0] weight_base_addr;
    wire [7:0]   input_base_addr;
    wire [2:0]           tile_number; 
    //assign input_base_addr = tile_number * N + 1; 
    assign input_base_addr = 8'b00000001; // 固定从0开始读输入，简化设计
    assign weight_base_addr = tile_number * N; 

    // ── valid ctrl ───────────────────────────────────────────────
    wire [11:0]                    valid_ctrl_pipeline;
    wire [11:0]                    valid_ctrl_layering;
    wire [11:0]                    valid_ctrl;
    assign valid_ctrl = valid_ctrl_pipeline | valid_ctrl_layering;

    // ── weight ctrl ──────────────────────────────────────────────
    wire [N_MACS-1:0]              weight_ctrl;
    wire [2:0]                     load_weights;
    wire                           weight_busy;

    // ── busy / ready ─────────────────────────────────────────────
    wire                           valid_pipeline_busy;
    wire                           layering_busy;
    wire                           layer_ready;
    assign busy = valid_pipeline_busy | layering_busy;

    // ── data ─────────────────────────────────────────────────────
    wire signed [ACC_W-1:0]        a_in;
    wire signed [ACC_W-1:0]        w_0, w_1, w_2, w_3;
    
    wire [$clog2(MEM_DEPTH)-1:0]   w_addr;
    wire [N_MACS-1:0]              clear;
    assign clear = {N_MACS{clear_all}};

    wire input_if_valid;
    wire weight_if_valid;


    // ── prime signals ────────────────────────────────────────────
    wire prime_input_en;
    wire prime_weight_en;

    // ── BRAM enable with prime OR ────────────────────────────────
    wire input_bram_en_raw;    // from input_mem_if
    wire weight_bram_en_a_raw; // from weight_mem_if
    wire weight_bram_en_b_raw; // from weight_mem_if

    assign input_bram_en    = input_bram_en_raw    | prime_input_en;
    assign weight_bram_en_a = weight_bram_en_a_raw | prime_weight_en;
    assign weight_bram_en_b = weight_bram_en_b_raw | prime_weight_en;


    top_ctrl u_top_ctrl (
        .clk                    (clk),
        .rst                    (rst),
        .start                  (start),
        .valid_ctrl_busy        (valid_pipeline_busy),
        .layer_ctrl_busy        (layering_busy),
        .input_if_valid         (input_if_valid),
        .weight_if_valid        (weight_if_valid),

        .tile_number         (tile_number),
        .mode                   (mode),
        .start_valid_pipeline   (start_valid_pipeline),
        .start_weights          (start_weights),
        .start_layering         (start_layering),
        .start_input            (start_input),
        .done                   (done),

        .prime_input_en     (prime_input_en),
        .prime_weight_en    (prime_weight_en)
    );
   


    
    // Valid pipeline control
    valid_pipeline_ctrl u_valid_pipeline_ctrl (
        .clk        (clk),
        .rst        (rst),
        .start      (start_valid_pipeline),
        .load_ready (weight_if_valid),

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
        .load_ready (), // leave blank
        .layer_ready (layer_ready)
    );
    
    // Weight memory interface (with BRAM ports)
    weight_mem_if #(

    ) u_weight_mem_if (
        .clk         (clk),
        .rst         (rst),


        .weight_base_addr     (weight_base_addr),
        .mode     (mode),

        // BRAM interface - directly to top ports
        .addr_a   (weight_bram_addr_a),
        .addr_b     (weight_bram_addr_b),

        .en_a   (weight_bram_en_a_raw),
        .en_b   (weight_bram_en_b_raw),

        .dout_a (weight_bram_dout_a),
        .dout_b (weight_bram_dout_b),

        .w0         (w_0),
        .w1         (w_1),
        .w2         (w_2),
        .w3         (w_3),
        

        .valid  (weight_if_valid),
        .done()

    );


    // Input memory interface (with BRAM ports)
    input_mem_if #(

    ) u_input_mem_if (
        .clk       (clk),
        .rst       (rst),
        .load_en   (start_input),
        .base_addr  (input_base_addr),

        // BRAM interface - directly to top ports
        .bram_addr (input_bram_addr),
        .bram_en   (input_bram_en_raw),
        .bram_dout (input_bram_dout),
        .a_out     (a_in),
        .valid      (input_if_valid)
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

        .acc_sel (tile_number),
        
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