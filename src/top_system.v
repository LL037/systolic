// top_system_nn.v
// NxN matrix-vector multiply using a fixed 2x2 physical MAC array.
// All modules are parameterized by N (matrix dimension).
//
// Memory layout assumptions:
//   Weight BRAM: row-major, each address holds [w3,w2,w1,w0] for one column
//                of the current row_tile pair.
//                For row_tile t, rows 2t and 2t+1 weights are interleaved.
//   Input BRAM:  x[0..N-1] stored sequentially, replayed each row_tile pass.

module top_system_nn #(
    parameter W         = 8,
    parameter ACC_W     = 16,
    parameter N         = 4,          // Matrix dimension (must be divisible by 4)
    parameter N_MACS    = 4,
    parameter NUM_ACC   = 8,          // >= N/2
    parameter MEM_DEPTH = 256
)(
    input  wire                           clk,
    input  wire                           rst,
    input  wire                           start,
    input  wire                           clear_all,

    // Weight BRAM interface
    output wire [$clog2(MEM_DEPTH)-1:0]   weight_bram_addr,
    output wire                           weight_bram_en,
    input  wire [N_MACS*ACC_W-1:0]        weight_bram_dout,

    // Input BRAM interface
    output wire [$clog2(MEM_DEPTH)-1:0]   input_bram_addr,
    output wire                           input_bram_en,
    input  wire [ACC_W-1:0]               input_bram_dout,

    // Status
    output wire                           busy,
    output wire                           done,

    // Results
    output wire signed [ACC_W-1:0]        acc_out_0,
    output wire signed [ACC_W-1:0]        acc_out_1,
    output wire signed [ACC_W-1:0]        acc_out_2,
    output wire signed [ACC_W-1:0]        acc_out_3,
    output wire [N_MACS-1:0]              valid_out

);

    // Internal control wires
    wire [11:0] valid_ctrl_pipeline;
    wire [11:0] valid_ctrl_layering;
    wire [11:0] valid_ctrl = valid_ctrl_pipeline | valid_ctrl_layering;

    wire [N_MACS-1:0] weight_ctrl;
    wire [2:0]        load_weights;
    wire              load_ready;
    wire              layer_ready;

    wire              valid_pipeline_busy;
    wire              layering_busy;
    wire              weight_busy;

    wire [2:0]        mode;
    wire              start_valid_pipeline;
    wire              start_weights;
    wire              start_layering;
    wire              start_input;

    wire signed [ACC_W-1:0] a_in;
    wire signed [ACC_W-1:0] w_0, w_1, w_2, w_3;

    wire [2:0] acc_sel_tile;
    wire next_tile;
    wire next_tile_ready;

    assign busy = valid_pipeline_busy | layering_busy;

    top_ctrl_nn #(.N(N)) u_top_ctrl (
        .clk                  (clk),
        .rst                  (rst),
        .start                (start),
        .valid_ctrl_busy      (valid_pipeline_busy),
        .layer_ctrl_busy      (layering_busy),
        .next_tile_ready     (next_tile_ready),

        .next_tile      (next_tile), 
        .mode                 (mode),
        .start_valid_pipeline (start_valid_pipeline),
        .start_layering       (start_layering),
        .start_weights        (start_weights),
        .start_input          (start_input),
        .done                 (done)
    );

    tile_ctrl_nn #(.N(N)) u_tile_ctrl (
        .clk        (clk),
        .rst        (rst),
        .next_tile   (next_tile),
    
        .next_tile_ready(next_tile_ready),
        .acc_sel_tile (acc_sel_tile)
    );

    valid_pipeline_ctrl_nn #(.N(N)) u_valid_pipeline (
        .clk        (clk),
        .rst        (rst),
        .start      (start_valid_pipeline),
        .load_ready (load_ready),

        .valid_ctrl (valid_ctrl_pipeline),
        .busy       (valid_pipeline_busy)
    );


    layering_pipeline_ctrl_nn u_layering (
        .clk        (clk),
        .rst        (rst),
        .start      (start_layering),
        .layer_ready(layer_ready),

        .valid_ctrl (valid_ctrl_layering),
        .busy       (layering_busy)
    );

  
    weight_pipeline_ctrl_nn #(.N_MACS(N_MACS)) u_weight_ctrl (
        .clk        (clk),
        .rst        (rst),
        .start      (start_weights),
        .mode       (mode),

        .weight_ctrl(weight_ctrl),
        .load       (load_weights),
        .busy       (weight_busy),
        .load_ready (load_ready),
        .layer_ready(layer_ready)
    );


    weight_mem_if #(
        .N_MACS    (N_MACS),
        .DATA_W    (ACC_W),
        .MEM_DEPTH (MEM_DEPTH)
    ) u_weight_mem (
        .clk        (clk),
        .rst        (rst),
        .load       (load_weights),
        .bram_addr  (weight_bram_addr),
        .bram_en    (weight_bram_en),
        .bram_dout  (weight_bram_dout),
        .load_ready (),
        .layer_ready(layer_ready),
        .w_addr     (),
        .w_0        (w_0),
        .w_1        (w_1),
        .w_2        (w_2),
        .w_3        (w_3)
    );

    input_mem_if #(
        .DATA_W    (ACC_W),
        .MEM_DEPTH (MEM_DEPTH)
    ) u_input_mem (
        .clk       (clk),
        .rst       (rst),
        .load_en   (start_input),
        .bram_addr (input_bram_addr),
        .bram_en   (input_bram_en),
        .bram_dout (input_bram_dout),
        .in_addr   (),
        .a_out     (a_in)
    );

    mac_array_nn #(
        .W      (W),
        .ACC_W  (ACC_W),
        .N_MACS (N_MACS),
        .NUM_ACC(NUM_ACC)
    ) u_mac_array (
        .clk            (clk),
        .rst            (rst),
        .valid_ctrl     (valid_ctrl),
        .clear          ({N_MACS{clear_all}}),
        .valid_weight_in(weight_ctrl),
        .a_in           (a_in),
        .w_0            (w_0),
        .w_1            (w_1),
        .w_2            (w_2),
        .w_3            (w_3),
        .acc_sel_tile   (acc_sel_tile),
        .acc_out_0      (acc_out_0),
        .acc_out_1      (acc_out_1),
        .acc_out_2      (acc_out_2),
        .acc_out_3      (acc_out_3),
        .valid_out      (valid_out)
    );

endmodule