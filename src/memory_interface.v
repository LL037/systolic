module input_mem_if #(
    parameter integer N           = 4,
    parameter integer DATA_W      = 16,
    parameter integer ADDR_W      = 8,
    parameter integer START_DELAY = 0   // 对齐 weight_mem_if 的 F1+F2+data_cnt lag
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              load_en,
    input  wire [ADDR_W-1:0] base_addr,

    output reg  [ADDR_W-1:0] bram_addr,
    output reg               bram_en,
    input  wire [DATA_W-1:0] bram_dout,

    output wire [DATA_W-1:0] a_out,
    output wire              valid,
    output wire              done
);
    localparam CNT_W = $clog2(N+2);

    // ── 移位寄存器延迟链 ─────────────────────────────────────
    // load_en 从 bit0 移入，START_DELAY 拍后从最高位输出
    reg [START_DELAY-1:0] delay_sr;
    wire                  load_en_dly = delay_sr[START_DELAY-1];

    reg [CNT_W-1:0] addr_cnt;
    reg [CNT_W-1:0] data_cnt;

    always @(posedge clk) begin
        if (rst) begin
            delay_sr  <= {START_DELAY{1'b0}};
            addr_cnt  <= {CNT_W{1'b0}};
            data_cnt  <= {CNT_W{1'b0}};
            bram_addr <= {ADDR_W{1'b0}};
            bram_en   <= 1'b0;
        end else begin
            // ── 移位：load_en 从低位移入 ─────────────────────
            delay_sr <= {delay_sr[START_DELAY-2:0], load_en};

            // ── data_cnt 跟踪 addr_cnt（1拍滞后）────────────
            data_cnt <= addr_cnt;

            if (addr_cnt == 0) begin
                if (load_en_dly) begin
                    bram_addr <= base_addr;
                    bram_en   <= 1'b1;
                    addr_cnt  <= {{(CNT_W-1){1'b0}}, 1'b1};
                end else begin
                    bram_en <= 1'b0;
                end
            end else if (addr_cnt < N) begin
                bram_addr <= base_addr + {{(ADDR_W-CNT_W){1'b0}}, addr_cnt};
                bram_en   <= 1'b1;
                addr_cnt  <= addr_cnt + 1'b1;
            end else if (addr_cnt == N) begin
                // 所有地址发完，等 data_cnt 追上
                bram_en  <= 1'b0;
                addr_cnt <= addr_cnt + 1'b1;
            end else begin
                // addr_cnt == N+1：data_cnt 已捕获 N，安全复位
                addr_cnt <= {CNT_W{1'b0}};
            end
        end
    end

    assign valid = (data_cnt >= 1) && (data_cnt <= N);
    assign a_out = bram_dout;
    assign done  = (data_cnt == N);

endmodule


module weight_mem_if #(
    parameter N         = 4,
    parameter DATA_W    = 16,
    parameter MEM_DEPTH = 256
)(
    input  wire                           clk,
    input  wire                           rst,

    input  wire [7:0]                     weight_base_addr,
    input  wire [2:0]                     mode,

    output reg  [7:0]                     addr_a,
    output reg  [7:0]                     addr_b,
    output wire                           en_a,
    output wire                           en_b,
    input  wire [DATA_W-1:0]              dout_a,
    input  wire [DATA_W-1:0]              dout_b,

    output reg  [DATA_W-1:0]              w0,
    output reg  [DATA_W-1:0]              w1,
    output reg  [DATA_W-1:0]              w2,
    output reg  [DATA_W-1:0]              w3,

    output reg                            valid,
    output reg                            done
);

    localparam MODE_IDLE  = 3'b000;
    localparam MODE_LOAD  = 3'b001;
    localparam MODE_LAYER = 3'b010;

    localparam IDLE   = 2'd0;
    localparam FETCH  = 2'd1;
    localparam STREAM = 2'd2;
    localparam DRAIN  = 2'd3;

    reg [1:0]               state;
    reg [$clog2(N+1)-1:0]   cnt;
    reg [2:0]               mode_lat;
    reg                     fetch_cnt;

    // ── 防重触发：ran=1 表示已跑过，mode 回 IDLE 时清除 ─────
    reg                     ran;

    assign en_a = ~rst;
    assign en_b = ~rst;

    // ─────────────────────────────────────────────────────────
    // MODE_LOAD timing (N=4, base=B), 2-cycle BRAM latency:
    //
    //  cycle:  IDLE   F1     F2      S(0)   S(1)   S(2)   S(3)  DRAIN
    //  addr_a: B      B+1    B+2     B+3    -      -      -      -
    //  addr_b: -      -      B+N     B+N+1  B+N+2  B+N+3  -      -
    //          ──────── 2-cycle BRAM latency ────────
    //  dout_a:                       d[B]   d[B+1] d[B+2] d[B+3] -
    //  dout_b:                       -      d[B+N] ...           d[B+N+3]
    //  w0:                           d[B]   d[B+1] d[B+2] d[B+3] 0
    //  w1:                           0      d[B+N] ...           d[B+N+3]
    //  valid:                        1      1      1      1      1
    //  done:                         0      0      0      0      1
    //
    // MODE_LAYER timing (N=4, base=B):
    //
    //  cycle:  IDLE   F1     F2      S(0)   S(1)   S(2)   S(3)
    //  addr_a: B      B+2    B+4     B+6    -      -      -
    //  addr_b: B+1    B+3    B+5     B+7    -      -      -
    //          ──────── 2-cycle BRAM latency ────────
    //  dout_a:                       d[B]   d[B+2] d[B+4] d[B+6]
    //  dout_b:                       d[B+1] d[B+3] d[B+5] d[B+7]
    //  w2/w3:                        valid  valid  valid  valid
    //  done:                         0      0      0      1
    // ─────────────────────────────────────────────────────────

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state     <= IDLE;
            cnt       <= 0;
            fetch_cnt <= 0;
            mode_lat  <= 0;
            addr_a    <= 0;
            addr_b    <= 0;
            w0 <= 0; w1 <= 0; w2 <= 0; w3 <= 0;
            valid     <= 0;
            done      <= 0;
            ran       <= 0;
        end else begin
            valid <= 0;
            done  <= 0;

            // ── ran 清除：mode 回到 IDLE 时允许下次触发 ──────
            if (mode == MODE_IDLE)
                ran <= 0;

            case (state)

                IDLE: begin
                    // ◀ 关键：加 !ran 条件，跑完一次后不再重触发
                    if (!ran && (mode == MODE_LOAD || mode == MODE_LAYER)) begin
                        mode_lat  <= mode;
                        cnt       <= 0;
                        fetch_cnt <= 0;
                        ran       <= 1;          // ◀ 标记已触发
                        w0 <= 0; w1 <= 0; w2 <= 0; w3 <= 0;

                        if (mode == MODE_LOAD) begin
                            addr_a <= weight_base_addr;
                        end else begin
                            addr_a <= weight_base_addr;
                            addr_b <= weight_base_addr + 1;
                        end

                        state <= FETCH;
                    end
                end

                FETCH: begin
                    if (mode_lat == MODE_LOAD) begin
                        if (fetch_cnt == 0) begin
                            addr_a    <= addr_a + 1;
                            fetch_cnt <= 1;
                        end else begin
                            addr_a    <= addr_a + 1;
                            addr_b    <= weight_base_addr + N;
                            fetch_cnt <= 0;
                            state     <= STREAM;
                        end
                    end else begin
                        if (fetch_cnt == 0) begin
                            addr_a    <= addr_a + 2;
                            addr_b    <= addr_b + 2;
                            fetch_cnt <= 1;
                        end else begin
                            addr_a    <= addr_a + 2;
                            addr_b    <= addr_b + 2;
                            fetch_cnt <= 0;
                            state     <= STREAM;
                        end
                    end
                end

                STREAM: begin
                    if (mode_lat == MODE_LOAD) begin
                        w0    <= dout_a;
                        w1    <= (cnt == 0) ? {DATA_W{1'b0}} : dout_b;
                        valid <= 1;

                        if (cnt < N - 1) begin
                            addr_a <= addr_a + 1;
                            addr_b <= addr_b + 1;
                        end

                        if (cnt == N - 1) begin
                            state <= DRAIN;
                            cnt   <= 0;
                        end else begin
                            cnt <= cnt + 1;
                        end

                    end else begin
                        w2    <= dout_a;
                        w3    <= dout_b;
                        valid <= 1;

                        if (cnt < N - 1) begin
                            addr_a <= addr_a + 2;
                            addr_b <= addr_b + 2;
                        end

                        if (cnt == N - 1) begin
                            done  <= 1;
                            state <= IDLE;
                        end else begin
                            cnt <= cnt + 1;
                        end
                    end
                end

                DRAIN: begin
                    w0    <= 0;
                    w1    <= dout_b;
                    valid <= 1;
                    done  <= 1;
                    state <= IDLE;
                end

            endcase
        end
    end

endmodule