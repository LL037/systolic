module weight_mem_if #(
    parameter integer N_MACS     = 4,
    parameter integer DATA_W     = 16,
    parameter integer MEM_DEPTH  = 256,
    parameter        MEM_FILE    = "weights.mem"
)(
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     load_en,   // advance to next weight group

    output reg  [$clog2(MEM_DEPTH)-1:0] w_addr,
    output reg  [DATA_W-1:0]        w_0,
    output reg  [DATA_W-1:0]        w_1,
    output reg  [DATA_W-1:0]        w_2,
    output reg  [DATA_W-1:0]        w_3
);

    // One memory line stores N_MACS weights: {w3, w2, w1, w0}
    localparam integer LINE_W = N_MACS * DATA_W;

    reg [LINE_W-1:0] weight_mem [0:MEM_DEPTH-1];
    reg [LINE_W-1:0] mem_q;

    // Load weight file at startup
    initial begin
        if (MEM_FILE != "") begin
            $display("Loading weights from %s", MEM_FILE);
            $readmemh(MEM_FILE, weight_mem);
        end
    end

    // Address counter
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            w_addr <= 0;
        end else if (load_en) begin
            if (w_addr == MEM_DEPTH-1)
                w_addr <= 0;        // wrap around
            else
                w_addr <= w_addr + 1'b1;
        end
    end

    // Synchronous read + unpack
    always @(posedge clk) begin
        mem_q <= weight_mem[w_addr];
        {w_3, w_2, w_1, w_0} <= mem_q;
    end

endmodule

module input_mem_if #(
    parameter integer DATA_W     = 16,
    parameter integer MEM_DEPTH  = 256,
    parameter        MEM_FILE    = "input.mem"
)(
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     load_en,     // advance to next input
    output reg  [$clog2(MEM_DEPTH)-1:0] in_addr,
    output reg  [DATA_W-1:0]        a_out
);

    reg [DATA_W-1:0] input_mem [0:MEM_DEPTH-1];
    reg [DATA_W-1:0] mem_q;

    // Load input file at startup
    initial begin
        if (MEM_FILE != "") begin
            $display("Loading input data from %s", MEM_FILE);
            $readmemh(MEM_FILE, input_mem);
        end
    end

    // Address counter
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            in_addr <= 0;
        end else if (load_en) begin
            if (in_addr == MEM_DEPTH-1)
                in_addr <= 0;      // wrap around
            else
                in_addr <= in_addr + 1'b1;
        end
    end

    // Synchronous read
    always @(posedge clk) begin
        mem_q <= input_mem[in_addr];
        a_out <= mem_q;
    end

endmodule
