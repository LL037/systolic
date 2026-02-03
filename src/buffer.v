module weight_mem_if #(
    parameter N_MACS     = 4,
    parameter DATA_W     = 16,
    parameter MEM_DEPTH  = 256,
    parameter MEM_FILE   = "weights.mem",
    parameter USE_EXT_BRAM = 1,
    parameter integer BRAM_ADDR_W = $clog2(MEM_DEPTH) + $clog2((N_MACS*DATA_W)/8)
)(
    input  wire                          clk,
    input  wire                          rst,
    input  wire [2:0]                    load,
    output reg                           load_ready,
    output reg                           layer_ready,
    output reg  [$clog2(MEM_DEPTH)-1:0]  w_addr,
    output reg  [DATA_W-1:0]             w_0,
    output reg  [DATA_W-1:0]             w_1,
    output reg  [DATA_W-1:0]             w_2,
    output reg  [DATA_W-1:0]             w_3,
    output wire                          bram_en,
    output wire [((N_MACS*DATA_W)/8)-1:0] bram_we,
    output wire [BRAM_ADDR_W-1:0]        bram_addr,
    output wire [N_MACS*DATA_W-1:0]      bram_din,
    input  wire [N_MACS*DATA_W-1:0]      bram_dout
);

    localparam LINE_W = N_MACS * DATA_W;
    localparam HALF   = N_MACS / 2;
    localparam NUM_PAIRS = N_MACS / 2;

    (* ram_style = "block" *) reg [LINE_W-1:0] weight_mem [0:MEM_DEPTH-1];
    reg [LINE_W-1:0] line_q;
    localparam integer ADDR_LSB = $clog2(LINE_W / 8);
    localparam integer ADDR_W = $clog2(MEM_DEPTH);

    initial begin
        if (!USE_EXT_BRAM && MEM_FILE != "") begin
            $readmemh(MEM_FILE, weight_mem);
        end
    end

    generate
        if (USE_EXT_BRAM) begin : gen_weight_ext_bram
            always @(posedge clk) begin
                line_q <= bram_dout;
            end
        end else begin : gen_weight_internal
            always @(posedge clk) begin
                line_q <= weight_mem[w_addr];
            end
        end
    endgenerate

    assign bram_en = USE_EXT_BRAM;
    assign bram_we = {((N_MACS*DATA_W)/8){1'b0}};
    assign bram_din = {LINE_W{1'b0}};
    assign bram_addr = USE_EXT_BRAM
        ? {{(BRAM_ADDR_W-ADDR_W-ADDR_LSB){1'b0}}, w_addr, {ADDR_LSB{1'b0}}}
        : {BRAM_ADDR_W{1'b0}};

    // Streaming state
    reg streaming_lo;
    reg streaming_hi;
    reg [$clog2(N_MACS)-1:0] cnt_lo;
    reg [$clog2(N_MACS)-1:0] cnt_hi;

    // Address
    always @(posedge clk or posedge rst) begin
        if (rst)
            w_addr <= 0;
        else if (load == 3'b010 && !streaming_hi)
            w_addr <= (w_addr == MEM_DEPTH-1) ? 0 : w_addr + 1;
    end

    // Lower half: w0, w1 (diagonal pattern)
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            w_0 <= 0;
            w_1 <= 0;
            streaming_lo <= 1'b0;
            cnt_lo <= 0;
            load_ready <= 1'b0;
        end else begin
            load_ready <= 1'b0;
            
            if (load == 3'b001 && !streaming_lo) begin
                streaming_lo <= 1'b1;
                load_ready <= 1'b1;
                cnt_lo <= 0;
                w_0 <= line_q[0 +: DATA_W];
                w_1 <= 0;
            end
            else if (streaming_lo) begin
                cnt_lo <= cnt_lo + 1;
                
                if (cnt_lo + 1 < HALF)
                    w_0 <= line_q[DATA_W*(cnt_lo+1) +: DATA_W];
                else
                    w_0 <= 0;
                
                w_1 <= line_q[DATA_W*(HALF + cnt_lo) +: DATA_W];
                
                if (cnt_lo == HALF - 1)
                    streaming_lo <= 1'b0;
            end
        end
    end

    // Upper half: w2, w3 (sequential pairs)
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            w_2 <= 0;
            w_3 <= 0;
            streaming_hi <= 1'b0;
            cnt_hi <= 0;
            layer_ready <= 1'b0;
        end else begin
            layer_ready <= 1'b0;
            
            if (load == 3'b010 && !streaming_hi) begin
                streaming_hi <= 1'b1;
                layer_ready <= 1'b1;
                cnt_hi <= 0;
            end
            else if (streaming_hi) begin
                w_2 <= line_q[DATA_W*(2*cnt_hi)     +: DATA_W];
                w_3 <= line_q[DATA_W*(2*cnt_hi + 1) +: DATA_W];
                
                cnt_hi <= cnt_hi + 1;
                
                if (cnt_hi == NUM_PAIRS - 1)
                    streaming_hi <= 1'b0;
            end
        end
    end

endmodule


module input_mem_if #(
    parameter integer DATA_W     = 16,
    parameter integer MEM_DEPTH  = 256,
    parameter        MEM_FILE    = "input.mem",
    parameter USE_EXT_BRAM = 1,
    parameter integer BRAM_ADDR_W = $clog2(MEM_DEPTH) + $clog2(DATA_W/8)
)(
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     load_en,     // advance to next input
    output reg  [$clog2(MEM_DEPTH)-1:0] in_addr,
    output reg  [DATA_W-1:0]        a_out,
    output wire                    bram_en,
    output wire [(DATA_W/8)-1:0]   bram_we,
    output wire [BRAM_ADDR_W-1:0]  bram_addr,
    output wire [DATA_W-1:0]       bram_din,
    input  wire [DATA_W-1:0]       bram_dout
);

    (* ram_style = "block" *) reg [DATA_W-1:0] input_mem [0:MEM_DEPTH-1];
    reg [DATA_W-1:0] mem_q;

    // Load input file at startup
    initial begin
        if (!USE_EXT_BRAM && MEM_FILE != "") begin
            $display("Loading input data from %s", MEM_FILE);
            $readmemh(MEM_FILE, input_mem);
        end
    end

    reg primed;

    // Address counter + primed
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            in_addr <= 0;
            primed  <= 1'b0;
        end else if (load_en) begin
            primed <= 1'b1;
            if (in_addr == MEM_DEPTH-1)
                in_addr <= 0;
            else
                in_addr <= in_addr + 1'b1;
        end
    end

    // Synchronous read (default 0 before first load)
    generate
        if (USE_EXT_BRAM) begin : gen_input_ext_bram
            always @(posedge clk or posedge rst) begin
                if (rst) begin
                    mem_q <= {DATA_W{1'b0}};
                    a_out <= {DATA_W{1'b0}};
                end else begin
                    mem_q <= bram_dout;
                    if (primed)
                        a_out <= mem_q;
                    else
                        a_out <= {DATA_W{1'b0}};
                end
            end
        end else begin : gen_input_internal
            always @(posedge clk or posedge rst) begin
                if (rst) begin
                    mem_q <= {DATA_W{1'b0}};
                    a_out <= {DATA_W{1'b0}};   // default 0
                end else begin
                    mem_q <= input_mem[in_addr];
                    if (primed)
                        a_out <= mem_q;
                    else
                        a_out <= {DATA_W{1'b0}}; // hold 0 until first load_en
                end
            end
        end
    endgenerate

    localparam integer INPUT_ADDR_LSB = $clog2(DATA_W / 8);
    localparam integer INPUT_ADDR_W = $clog2(MEM_DEPTH);
    assign bram_en = USE_EXT_BRAM;
    assign bram_we = {(DATA_W/8){1'b0}};
    assign bram_din = {DATA_W{1'b0}};
    assign bram_addr = USE_EXT_BRAM
        ? {{(BRAM_ADDR_W-INPUT_ADDR_W-INPUT_ADDR_LSB){1'b0}}, in_addr, {INPUT_ADDR_LSB{1'b0}}}
        : {BRAM_ADDR_W{1'b0}};


endmodule
