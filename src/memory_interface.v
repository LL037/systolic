module input_mem_if #(
    parameter integer N         = 4,
    parameter integer DATA_W    = 16,
    parameter integer BRAM_W    = 16,
    parameter integer MEM_DEPTH = 256
)(
    input  wire                 clk,
    input  wire                 rst,
    input  wire                 load_en,
    input  wire [7:0]           base_addr,   // FIXED: 8-bit BRAM address

    output reg  [7:0]           bram_addr,   // FIXED: 8-bit BRAM address
    output wire                 bram_en,
    input  wire [15:0]          bram_dout,   // FIXED: 16-bit BRAM data out

    output reg  [DATA_W-1:0]    a_out,
    output reg                  valid,
    output reg                  done
);
    // Sanity (optional): BRAM_W must match dout width and be divisible by DATA_W
    localparam integer WORDS_PER_ROW = BRAM_W / DATA_W;  // for 16/8 => 2

    assign bram_en = ~rst;

    localparam IDLE   = 3'd0;
    localparam WAIT1  = 3'd1;
    localparam WAIT2  = 3'd2;
    localparam STREAM = 3'd3;

    reg [2:0] state;

    reg [$clog2(N)-1:0]                 word_cnt;
    reg [$clog2(WORDS_PER_ROW)-1:0]     slot;
    reg [BRAM_W-1:0]                    row_buf;

    // Optional: flush on base_addr change (uncomment if needed)
    // reg [7:0] base_addr_q;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state     <= IDLE;
            word_cnt  <= 0;
            slot      <= 0;
            bram_addr <= 8'd0;
            row_buf   <= {BRAM_W{1'b0}};
            a_out     <= {DATA_W{1'b0}};
            valid     <= 1'b0;
            done      <= 1'b0;
            // base_addr_q <= 8'd0;
        end else begin
            valid <= 1'b0;
            done  <= 1'b0;

            // Optional flush logic
            // if (base_addr != base_addr_q) begin
            //     base_addr_q <= base_addr;
            //     state       <= IDLE;
            //     word_cnt    <= 0;
            //     slot        <= 0;
            // end

            case (state)
                IDLE: begin
                    if (load_en) begin
                        word_cnt  <= 0;
                        slot      <= 0;
                        bram_addr <= base_addr;
                        state     <= WAIT1;
                    end
                end

                WAIT1: state <= WAIT2;

                WAIT2: begin
                    row_buf <= bram_dout;   // 16-bit into row_buf (BRAM_W=16)
                    slot    <= 0;
                    state   <= STREAM;
                end

                STREAM: begin
                    a_out <= row_buf[slot*DATA_W +: DATA_W];
                    valid <= 1'b1;

                    if (word_cnt == N - 1) begin
                        done  <= 1'b1;
                        state <= IDLE;
                    end else begin
                        word_cnt <= word_cnt + 1;

                        if (slot == WORDS_PER_ROW - 1) begin
                            bram_addr <= bram_addr + 1;
                            state     <= WAIT1;
                        end else begin
                            slot <= slot + 1;
                        end
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule


module weight_mem_if #(
    parameter N         = 4,
    parameter DATA_W    = 64,
    parameter MEM_DEPTH = 256
)(
    input  wire                           clk,
    input  wire                           rst,

    input  wire [$clog2(MEM_DEPTH)-1:0]   weight_base_addr,
    input  wire [2:0]                     mode,   // 3'b001=load(diagonal)  3'b010=layer(direct)

    // dual-port BRAM (1-cycle read latency)
    output reg  [$clog2(MEM_DEPTH)-1:0]   addr_a,
    output reg  [$clog2(MEM_DEPTH)-1:0]   addr_b,
    output wire                           en_a,
    output wire                           en_b,
    input  wire [DATA_W-1:0]              dout_a,
    input  wire [DATA_W-1:0]              dout_b,

    output reg  [DATA_W-1:0]              w0,   // load: leads
    output reg  [DATA_W-1:0]              w1,   // load: trails 1 cycle
    output reg  [DATA_W-1:0]              w2,   // layer: port A
    output reg  [DATA_W-1:0]              w3,   // layer: port B

    output reg                            valid,
    output reg                            done
);
    localparam MODE_LOAD  = 3'b001;   // diagonal, w0/w1
    localparam MODE_LAYER = 3'b010;   // direct dual-port, w2/w3

    localparam IDLE   = 2'd0;
    localparam FETCH  = 2'd1;   // wait 1 cycle for BRAM latency
    localparam STREAM = 2'd2;
    localparam DRAIN  = 2'd3;   // mode load only: flush last w1

    reg [1:0]                   state;
    reg [$clog2(N+1)-1:0]       cnt;
    reg [2:0]                   mode_lat;
    reg [DATA_W-1:0]            w0_prev;

    assign en_a = ~rst;
    assign en_b = ~rst;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state    <= IDLE;
            cnt      <= 0;
            mode_lat <= 0;
            w0_prev  <= 0;
            addr_a   <= 0; addr_b <= 0;
            w0<=0; w1<=0; w2<=0; w3<=0;
            valid <= 0; done <= 0;
        end else begin
            valid <= 0;
            done  <= 0;

            case (state)

                IDLE: begin
                    if (mode == MODE_LOAD || mode == MODE_LAYER) begin
                        mode_lat <= mode;
                        w0_prev  <= 0;
                        w0<=0; w1<=0; w2<=0; w3<=0;
                        cnt      <= 0;
                        addr_a   <= weight_base_addr;
                        addr_b   <= weight_base_addr + 1;
                        state    <= FETCH;
                    end
                end

                // absorb 1-cycle BRAM latency, pre-issue second addr
                FETCH: begin
                    if (mode_lat == MODE_LOAD)
                        addr_a <= addr_a + 1;
                    else begin
                        addr_a <= addr_a + 2;
                        addr_b <= addr_b + 2;
                    end
                    state <= STREAM;
                end

                STREAM: begin
                    if (mode_lat == MODE_LOAD) begin
                        // ── diagonal: w0 current, w1 previous ────
                        w0      <= dout_a;
                        w1      <= w0_prev;
                        w0_prev <= dout_a;
                        valid   <= 1;

                        if (cnt < N - 1)
                            addr_a <= addr_a + 1;

                        if (cnt == N - 1) begin
                            state <= DRAIN;
                            cnt   <= 0;
                        end else
                            cnt <= cnt + 1;

                    end else begin
                        // ── direct: w2=portA, w3=portB ───────────
                        w2    <= dout_a;
                        w3    <= dout_b;
                        valid <= 1;

                        if (cnt < N/2 - 1) begin
                            addr_a <= addr_a + 2;
                            addr_b <= addr_b + 2;
                        end

                        if (cnt == N/2 - 1) begin
                            done  <= 1;
                            state <= IDLE;
                        end else
                            cnt <= cnt + 1;
                    end
                end

                // mode load only: output final w1
                DRAIN: begin
                    w0    <= 0;
                    w1    <= w0_prev;
                    valid <= 1;
                    done  <= 1;
                    state <= IDLE;
                end

            endcase
        end
    end

endmodule