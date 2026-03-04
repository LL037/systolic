// ============================================================
// input_mem_if.v
//
// N words from BRAM (registered output, 1-cycle latency).
// First valid + a_out appears ONE clock after start.
//
// Timing (N=4, base=A):
//   edge:       T0     T1     T2     T3     T4     T5
//   start:       1      0      -      -      -      -
//   bram_addr:  [A]   [A+1]  [A+2]  [A+3]   -      -
//   bram_en:     1      1      1      1       0      0
//   bram_dout:   x     d[0]  d[1]   d[2]   d[3]    -
//   valid:       0      1      1      1      1       0
//   a_out:       x     d[0]  d[1]   d[2]   d[3]    -
//   done:        0      0      0      0      1       0
// ============================================================

module input_mem_if #(
    parameter integer N      = 4,
    parameter integer DATA_W = 16,
    parameter integer ADDR_W = 8
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              start,
    input  wire [ADDR_W-1:0] base_addr,

    output reg  [ADDR_W-1:0] bram_addr,
    output reg               bram_en,
    input  wire [DATA_W-1:0] bram_dout,

    output wire [DATA_W-1:0] a_out,
    output wire              valid,
    output wire              done
);
    // addr_cnt: 0=idle, 1..N = addresses sent so far
    // data_cnt: mirrors addr_cnt delayed by 1 cycle (= bram latency)
    localparam CNT_W = $clog2(N+1);

    reg [CNT_W-1:0] addr_cnt;   // number of addresses dispatched
    reg [CNT_W-1:0] data_cnt;   // lags addr_cnt by 1

    always @(posedge clk) begin
        if (rst) begin
            addr_cnt  <= {CNT_W{1'b0}};
            data_cnt  <= {CNT_W{1'b0}};
            bram_addr <= {ADDR_W{1'b0}};
            bram_en   <= 1'b0;
        end else begin
            // data_cnt always lags addr_cnt by 1
            data_cnt <= addr_cnt;

            if (addr_cnt == 0) begin
                if (start) begin
                    bram_addr <= base_addr;
                    bram_en   <= 1'b1;
                    addr_cnt  <= {{(CNT_W-1){1'b0}}, 1'b1};
                end
            end else if (addr_cnt < N) begin
                // send next address
                bram_addr <= base_addr + {{(ADDR_W-CNT_W){1'b0}}, addr_cnt};
                bram_en   <= 1'b1;
                addr_cnt  <= addr_cnt + 1'b1;
            end else begin
                // addr_cnt == N: all addresses sent
                bram_en   <= 1'b0;
                addr_cnt  <= {CNT_W{1'b0}};  // reset for next start
            end
        end
    end

    // valid: bram_dout is meaningful when data_cnt = 1..N
    //   data_cnt=1 means addr_cnt was 1 last cycle → addr[0] was sent → d[0] ready
    assign valid = (data_cnt >= 1) && (data_cnt <= N);
    assign a_out = bram_dout;
    assign done  = (data_cnt == N);

endmodule


module weight_mem_if #(
    parameter N         = 4,
    parameter DATA_W    = 64,
    parameter MEM_DEPTH = 256
)(
    input  wire                           clk,
    input  wire                           rst,

    input  wire [7:0]   weight_base_addr,
    input  wire [2:0]                     mode,   // 3'b001=load(diagonal)  3'b010=layer(direct)

    // dual-port BRAM (1-cycle read latency)
    output reg  [7:0]   addr_a,
    output reg  [7:0]   addr_b,
    output wire                           en_a,
    output wire                           en_b,
    input  wire [63:0]              dout_a,
    input  wire [63:0]              dout_b,

    output reg  [15:0]              w0,   // load: leads
    output reg  [15:0]              w1,   // load: trails 1 cycle
    output reg  [15:0]              w2,   // layer: port A
    output reg  [15:0]              w3,   // layer: port B

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