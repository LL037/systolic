module input_mem_if #(
    parameter integer N          = 4,
    parameter integer DATA_W     = 16,
    parameter integer BRAM_W     = 64,
    parameter integer MEM_DEPTH  = 256
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       load_en,
    input  wire [$clog2(MEM_DEPTH)-1:0] base_addr,

    output reg  [$clog2(MEM_DEPTH)-1:0] bram_addr,
    output wire                          bram_en,
    input  wire [BRAM_W-1:0]             bram_dout,

    output reg  [DATA_W-1:0]             a_out,
    output reg  [$clog2(N)-1:0]          in_idx
);

    localparam integer WORDS_PER_BRAM = BRAM_W / DATA_W;   // 4

    assign bram_en = ~rst;

    reg [$clog2(N)-1:0]              word_idx;
    reg [$clog2(WORDS_PER_BRAM)-1:0] slot_idx;
    reg [BRAM_W-1:0]                 row_buf;
    wire [$clog2(MEM_DEPTH)-1:0]     row_idx = word_idx >> $clog2(WORDS_PER_BRAM);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            word_idx  <= 0;
            slot_idx  <= 0;
            bram_addr <= 0;
            row_buf   <= 0;
            a_out     <= 0;
            in_idx    <= 0;
        end else begin
            row_buf <= bram_dout;

            if (load_en) begin
                a_out  <= row_buf[slot_idx * DATA_W +: DATA_W];
                in_idx <= word_idx;

                if (word_idx == N - 1) begin
                    word_idx  <= 0;
                    slot_idx  <= 0;
                    bram_addr <= base_addr;
                end else begin
                    word_idx <= word_idx + 1;
                    if (slot_idx == WORDS_PER_BRAM - 1) begin
                        slot_idx  <= 0;
                        bram_addr <= base_addr + row_idx + 1;
                    end else begin
                        slot_idx <= slot_idx + 1;
                    end
                end
            end else begin
                bram_addr <= base_addr + row_idx;
            end
        end
    end

endmodule
// weight_mem_if.v
// Reads two weight columns from 64-bit BRAM and outputs to MACs.
// Layer1 (layer_sel=0): diagonal feed → w0/w1, N+1 cycles
//   cycle k: w0=col0[k], w1=col1[k-1]  (w1=0 on k=0, w0=0 on k=N)
// Layer2 (layer_sel=1): simultaneous feed → w2/w3, N cycles
//   cycle k: w2=col0[k], w3=col1[k]
// Note: last valid data appears on the same cycle busy deasserts.

module weight_mem_if #(
    parameter integer N            = 4,
    parameter integer MACS_PER_ROW = 2,
    parameter integer DATA_W       = 16,
    parameter integer BRAM_W       = 64,
    parameter integer MEM_DEPTH    = 256
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       start,
    input  wire [$clog2(MEM_DEPTH)-1:0] base_addr,
    input  wire                          layer_sel,

    output reg  [$clog2(MEM_DEPTH)-1:0] bram_addr,
    output wire                          bram_en,
    input  wire [BRAM_W-1:0]             bram_dout,

    output reg  [DATA_W-1:0]             w0,
    output reg  [DATA_W-1:0]             w1,
    output reg  [DATA_W-1:0]             w2,
    output reg  [DATA_W-1:0]             w3,

    output reg                           busy,
    output reg                           load_ready
);

    localparam integer WORDS_PER_BRAM    = BRAM_W / DATA_W;       // 4
    localparam integer BRAM_ROWS_PER_COL = N / WORDS_PER_BRAM;    // N/4

    // States
    localparam P_IDLE    = 3'd0;
    localparam P_RD_COL0 = 3'd1;   // issue addr for col0 rows (1 cycle per row)
    localparam P_LD_COL0 = 3'd2;   // latch bram_dout for col0
    localparam P_RD_COL1 = 3'd3;   // issue addr for col1 rows
    localparam P_LD_COL1 = 3'd4;   // latch bram_dout for col1, arm load_ready
    localparam P_DIAG    = 3'd5;   // output weights

    reg [DATA_W-1:0] col0_buf [0:N-1];
    reg [DATA_W-1:0] col1_buf [0:N-1];

    reg [2:0]                              phase;
    reg [$clog2(BRAM_ROWS_PER_COL+1)-1:0] rd_cnt;  // counts rows fetched
    reg [$clog2(N+1)-1:0]                 out_cnt;  // counts diagonal output cycles

    assign bram_en = ~rst;

    integer i;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            phase      <= P_IDLE;
            rd_cnt     <= 0;
            out_cnt    <= 0;
            bram_addr  <= 0;
            w0 <= 0; w1 <= 0; w2 <= 0; w3 <= 0;
            busy       <= 1'b0;
            load_ready <= 1'b0;
            for (i = 0; i < N; i = i + 1) begin
                col0_buf[i] <= 0;
                col1_buf[i] <= 0;
            end
        end else begin
            load_ready <= 1'b0;

            case (phase)

                // ---------------------------------------------------------
                P_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        // Issue first col0 address; BRAM data appears next cycle
                        bram_addr <= base_addr;
                        rd_cnt    <= 0;
                        busy      <= 1'b1;
                        phase     <= P_RD_COL0;
                    end
                end

                // ---------------------------------------------------------
                // P_RD_COL0: addr is valid, BRAM is reading.
                // Each cycle: latch current dout, advance addr for next row.
                // After all BRAM_ROWS_PER_COL rows issued+latched → move to col1.
                P_RD_COL0: begin
                    // Latch the row that was issued in the previous cycle
                    begin : latch0
                        integer w;
                        for (w = 0; w < WORDS_PER_BRAM; w = w + 1)
                            if (rd_cnt * WORDS_PER_BRAM + w < N)
                                col0_buf[rd_cnt * WORDS_PER_BRAM + w] <= bram_dout[w*DATA_W +: DATA_W];
                    end

                    if (rd_cnt < BRAM_ROWS_PER_COL - 1) begin
                        // More col0 rows to fetch
                        bram_addr <= base_addr + rd_cnt + 1;
                        rd_cnt    <= rd_cnt + 1;
                    end else begin
                        // All col0 rows latched; issue first col1 address
                        bram_addr <= base_addr + BRAM_ROWS_PER_COL;
                        rd_cnt    <= 0;
                        phase     <= P_RD_COL1;
                    end
                end

                // ---------------------------------------------------------
                // P_RD_COL1: same pattern for col1
                P_RD_COL1: begin
                    begin : latch1
                        integer w;
                        for (w = 0; w < WORDS_PER_BRAM; w = w + 1)
                            if (rd_cnt * WORDS_PER_BRAM + w < N)
                                col1_buf[rd_cnt * WORDS_PER_BRAM + w] <= bram_dout[w*DATA_W +: DATA_W];
                    end

                    if (rd_cnt < BRAM_ROWS_PER_COL - 1) begin
                        bram_addr <= base_addr + BRAM_ROWS_PER_COL + rd_cnt + 1;
                        rd_cnt    <= rd_cnt + 1;
                    end else begin
                        // All col1 rows latched; arm load_ready 1 cycle before DIAG
                        rd_cnt     <= 0;
                        out_cnt    <= 0;
                        load_ready <= 1'b1;
                        phase      <= P_DIAG;
                    end
                end

                // ---------------------------------------------------------
                P_DIAG: begin
                    if (!layer_sel) begin
                        // Layer1 diagonal: w0=col0[k], w1=col1[k-1]
                        w0 <= (out_cnt <= N-1) ? col0_buf[out_cnt] : {DATA_W{1'b0}};
                        w1 <= (out_cnt >= 1)   ? col1_buf[out_cnt-1] : {DATA_W{1'b0}};
                        w2 <= {DATA_W{1'b0}};
                        w3 <= {DATA_W{1'b0}};
                        if (out_cnt == N) begin
                            out_cnt <= 0; phase <= P_IDLE; busy <= 1'b0;
                        end else
                            out_cnt <= out_cnt + 1;
                    end else begin
                        // Layer2 simultaneous: w2=col0[k], w3=col1[k]
                        w0 <= {DATA_W{1'b0}};
                        w1 <= {DATA_W{1'b0}};
                        w2 <= col0_buf[out_cnt];
                        w3 <= col1_buf[out_cnt];
                        if (out_cnt == N-1) begin
                            out_cnt <= 0; phase <= P_IDLE; busy <= 1'b0;
                        end else
                            out_cnt <= out_cnt + 1;
                    end
                end

                default: phase <= P_IDLE;
            endcase
        end
    end

endmodule