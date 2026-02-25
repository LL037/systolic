module input_mem_if #(
    parameter integer DATA_W     = 16,
    parameter integer MEM_DEPTH  = 256
)(
    input  wire                            clk,
    input  wire                            rst,
    input  wire                            load_en,     // advance to next input
    
    // BRAM Interface - directly connect to Block Memory Generator
    output reg  [$clog2(MEM_DEPTH)-1:0]    bram_addr,   // Address to BRAM
    output wire                            bram_en,      // BRAM enable
    input  wire [DATA_W-1:0]               bram_dout,   // Data from BRAM
    
    // Output
    output reg  [$clog2(MEM_DEPTH)-1:0]    in_addr,     // Current address (for debug/status)
    output reg  [DATA_W-1:0]               a_out
);

    reg [DATA_W-1:0] mem_q;
    reg primed;   // becomes 1 after first load_en

    // BRAM enable - always enabled when not in reset
    assign bram_en = ~rst;

    // Address counter + primed
    // Note: bram_addr leads in_addr by 1 cycle for read latency compensation
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            in_addr   <= 0;
            bram_addr <= 0;
            primed    <= 1'b0;
        end else if (load_en) begin
            primed <= 1'b1;
            if (in_addr == MEM_DEPTH-1) begin
                in_addr   <= 0;
                bram_addr <= 1;  // Pre-fetch next address
            end else begin
                in_addr   <= in_addr + 1'b1;
                bram_addr <= (in_addr + 2 >= MEM_DEPTH) ? 0 : in_addr + 2;  // Pre-fetch
            end
        end
    end

    // Synchronous read from BRAM (default 0 before first load)
    // BRAM has 1 cycle read latency, so bram_dout corresponds to bram_addr from previous cycle
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mem_q <= {DATA_W{1'b0}};
            a_out <= {DATA_W{1'b0}};
        end else begin
            mem_q <= bram_dout;  // Capture BRAM output
            if (primed)
                a_out <= mem_q;
            else
                a_out <= {DATA_W{1'b0}}; // hold 0 until first load_en
        end
    end

endmodule

module weight_mem_if #(
    parameter N_MACS     = 4,
    parameter DATA_W     = 16,
    parameter MEM_DEPTH  = 256
)(
    input  wire                          clk,
    input  wire                          rst,
    input  wire [2:0]                    load,  // 001 = load lower half, 010 = load upper half, 000 = idle
    output reg                           load_ready,
    output reg                           layer_ready,
    
    // BRAM Interface - directly connect to Block Memory Generator
    output reg  [$clog2(MEM_DEPTH)-1:0]  bram_addr,    // Address to BRAM
    output wire                          bram_en,       // BRAM enable
    input  wire [N_MACS*DATA_W-1:0]      bram_dout,    // Data from BRAM (one line)
    
    // Weight outputs to MAC array
    output reg  [$clog2(MEM_DEPTH)-1:0]  w_addr,       // Current address (for debug/status)
    output reg  [DATA_W-1:0]             w_0,
    output reg  [DATA_W-1:0]             w_1,
    output reg  [DATA_W-1:0]             w_2,
    output reg  [DATA_W-1:0]             w_3
);

    localparam LINE_W = N_MACS * DATA_W;
    localparam HALF   = N_MACS / 2;
    localparam NUM_PAIRS = N_MACS / 2;

    // BRAM enable - always enabled when not in reset
    assign bram_en = ~rst;

    // Use BRAM output directly (replaces weight_mem[w_addr])
    wire [LINE_W-1:0] line_cur = bram_dout;

    // Streaming state
    reg streaming_lo;
    reg streaming_hi;
    reg [$clog2(N_MACS)-1:0] cnt_lo;
    reg [$clog2(N_MACS)-1:0] cnt_hi;

    // Address - drives both w_addr and bram_addr
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            w_addr    <= 0;
            bram_addr <= 0;
        end else if (load == 3'b010 && !streaming_hi) begin
            w_addr    <= (w_addr == MEM_DEPTH-1) ? 0 : w_addr + 1;
            bram_addr <= (w_addr == MEM_DEPTH-1) ? 0 : w_addr + 1;
        end
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
                w_0 <= line_cur[0 +: DATA_W];
                w_1 <= 0;
            end
            else if (streaming_lo) begin
                cnt_lo <= cnt_lo + 1;
                
                if (cnt_lo + 1 < HALF)
                    w_0 <= line_cur[DATA_W*(cnt_lo+1) +: DATA_W];
                else
                    w_0 <= 0;
                
                w_1 <= line_cur[DATA_W*(HALF + cnt_lo) +: DATA_W];
                
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
                w_2 <= line_cur[DATA_W*(2*cnt_hi)     +: DATA_W];
                w_3 <= line_cur[DATA_W*(2*cnt_hi + 1) +: DATA_W];
                
                cnt_hi <= cnt_hi + 1;
                
                if (cnt_hi == NUM_PAIRS - 1)
                    streaming_hi <= 1'b0;
            end
        end
    end

endmodule