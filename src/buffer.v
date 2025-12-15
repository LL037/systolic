module weight_mem_if #(
    parameter integer N_MACS     = 4,
    parameter integer DATA_W     = 16,
    parameter integer MEM_DEPTH  = 256,
    parameter        MEM_FILE    = "D:/systolic/sim/weights.mem"
)(
    input  wire                          clk,
    input  wire                          rst,

    input  wire [2:0]                    load,    // 3'b001: load w0,w1 ; 3'b010: load w2,w3

    output reg  [$clog2(MEM_DEPTH)-1:0]  w_addr,
    output reg  [DATA_W-1:0]             w_0,
    output reg  [DATA_W-1:0]             w_1,
    output reg  [DATA_W-1:0]             w_2,
    output reg  [DATA_W-1:0]             w_3
);

    localparam integer LINE_W = N_MACS * DATA_W;
    localparam integer HALF   = N_MACS / 2;
    reg [LINE_W-1:0] weight_mem [0:MEM_DEPTH-1];

    initial begin
        if (MEM_FILE != "") begin
            $display("Loading weights from %s", MEM_FILE);
            $readmemh(MEM_FILE, weight_mem);
        end
    end

    // Current layer line (combinational read from ROM array)
    wire [LINE_W-1:0] line_d = weight_mem[w_addr];

    // next line (for skewed input only during loading)
    wire [$clog2(MEM_DEPTH)-1:0] w_addr_next =
        (w_addr == MEM_DEPTH-1) ? '0 : (w_addr + 1'b1);
    wire [LINE_W-1:0] line_next_d = weight_mem[w_addr_next];

    reg [2:0] phase;
    reg       streaming;

    reg [DATA_W-1:0] buf_w0 [0:N_MACS-1];
    reg [DATA_W-1:0] buf_w1 [0:N_MACS-1];

    integer i;

    // Address: advance only after finishing upper-half (load==010)
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            w_addr <= '0;
        end else if (load == 3'b010) begin
            if (w_addr == MEM_DEPTH-1) w_addr <= '0;
            else                       w_addr <= w_addr + 1'b1;
        end
    end

    // Output register: update only when load hits
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            w_0 <= '0; w_1 <= '0; w_2 <= '0; w_3 <= '0;
            phase <= '0;
            streaming <= 1'b0;
        end else begin
            // skewed streaming ONLY during loading (load==001)
            if (load == 3'b001) begin
                streaming <= 1'b1;
                phase <= '0;

                for (i = 0; i < N_MACS; i = i + 1) begin
                    buf_w0[i] <= line_d[DATA_W*i +: DATA_W];
                    buf_w1[i] <= line_next_d[DATA_W*i +: DATA_W];
                end

                // cycle 0
                w_0 <= line_d[DATA_W*0 +: DATA_W];
                w_1 <= '0;
            end
            else if (streaming) begin
                // w0: [1,2,3,4,0]
                if (phase < N_MACS)
                    w_0 <= buf_w0[phase];
                else
                    w_0 <= '0;

                // w1: [0,5,6,7,8]
                if (phase == 0)
                    w_1 <= '0;
                else if (phase <= N_MACS)
                    w_1 <= buf_w1[phase-1];
                else
                    w_1 <= '0;

                if (phase == N_MACS) begin
                    streaming <= 1'b0;
                    phase <= '0;
                end else begin
                    phase <= phase + 1'b1;
                end
            end
            else if (load == 3'b010) begin
                w_2 <= line_d[DATA_W*2 +: DATA_W];
                w_3 <= line_d[DATA_W*3 +: DATA_W];
            end
            // else: hold previous outputs
        end
    end

endmodule


module input_mem_if #(
    parameter integer DATA_W     = 16,
    parameter integer MEM_DEPTH  = 256,
    parameter        MEM_FILE    = "D:/systolic/sim/input.mem"
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
