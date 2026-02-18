// top_ctrl_nn.v
// Top-level sequencer for NxN matrix-vector multiplication on a 2x2 MAC array.
//
// Computation schedule for N=4 (example):
//   LOAD phase (row_tile=0):
//     Cycles 0..N-1 : stream x[0..N-1], feed w[0][*] to mac_0, w[1][*] to mac_1
//                     acc_sel=0 → y0 partial sums in acc[0] of mac_0/mac_1
//                     (tile2 mirrors with w[2][*],w[3][*] → acc[0] of mac_2/mac_3)
//   LAYER phase:
//     Read acc[0] from tile1 (y0,y1), read acc[0] from tile2 (y2,y3) → output
//
//   For general N (N must be divisible by 4 for full tile utilization):
//     row_tile = 0..(N/4)-1, each tile computes 2 output rows
//     acc_sel = row_tile during load, same row_tile during readout
//
// FSM states:
//   IDLE → ISSUE_LOAD → WAIT_LOAD → ISSUE_LAYER → WAIT_LAYER → (loop/DONE)

module top_ctrl_nn #(
    parameter N = 4   // Matrix dimension (must be even, >=2)
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       start,

    // Handshakes from sub-controllers
    input  wire       valid_ctrl_busy,
    input  wire       layer_ctrl_busy,

    // Current row-tile (which pair of output rows are being computed)
    output reg  [$clog2(N/2)-1:0] row_tile,

    // acc_sel for each tile (same value for both MACs in a tile)
    output reg  [2:0]             acc_sel_tile1,
    output reg  [2:0]             acc_sel_tile2,

    output reg  [2:0]             mode,          // 0:idle 1:load 2:layer
    output reg                    start_valid_pipeline,
    output reg                    start_layering,
    output reg                    start_weights,
    output reg                    start_input,
    output reg                    done
);

    localparam NUM_TILES = N / 4;  // number of row_tile iterations

    localparam [2:0]
        MODE_IDLE  = 3'd0,
        MODE_LOAD  = 3'd1,
        MODE_LAYER = 3'd2;

    localparam [3:0]
        S_IDLE          = 4'd0,
        S_ISSUE_LOAD    = 4'd1,
        S_WAIT_LOAD_ON  = 4'd2,
        S_WAIT_LOAD_OFF = 4'd3,
        S_ISSUE_LAYER   = 4'd4,
        S_WAIT_LAY_ON   = 4'd5,
        S_WAIT_LAY_OFF  = 4'd6,
        S_NEXT_TILE     = 4'd7;

    reg [3:0] state;
    reg [$clog2(N/2)-1:0] tile_cnt;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state                <= S_IDLE;
            mode                 <= MODE_IDLE;
            start_valid_pipeline <= 1'b0;
            start_layering       <= 1'b0;
            start_weights        <= 1'b0;
            start_input          <= 1'b0;
            done                 <= 1'b0;
            row_tile             <= 0;
            acc_sel_tile1        <= 3'd0;
            acc_sel_tile2        <= 3'd0;
            tile_cnt             <= 0;
        end else begin
            // Default: 1-cycle pulses
            start_valid_pipeline <= 1'b0;
            start_layering       <= 1'b0;
            start_weights        <= 1'b0;
            start_input          <= 1'b0;
            done                 <= 1'b0;

            case (state)
                // ---------------------------------------------------------
                S_IDLE: begin
                    mode     <= MODE_IDLE;
                    tile_cnt <= 0;
                    row_tile <= 0;
                    if (start && !valid_ctrl_busy && !layer_ctrl_busy)
                        state <= S_ISSUE_LOAD;
                end

                // ---------------------------------------------------------
                // LOAD phase: stream x[0..N-1], feed weight row pair
                // ---------------------------------------------------------
                S_ISSUE_LOAD: begin
                    mode                 <= MODE_LOAD;
                    acc_sel_tile1        <= tile_cnt[2:0];   // row pair index
                    acc_sel_tile2        <= tile_cnt[2:0];
                    start_weights        <= 1'b1;
                    start_input          <= 1'b1;
                    start_valid_pipeline <= 1'b1;
                    state                <= S_WAIT_LOAD_ON;
                end

                S_WAIT_LOAD_ON: begin
                    mode <= MODE_LOAD;
                    if (valid_ctrl_busy)
                        state <= S_WAIT_LOAD_OFF;
                end

                S_WAIT_LOAD_OFF: begin
                    mode <= MODE_LOAD;
                    if (!valid_ctrl_busy)
                        state <= S_ISSUE_LAYER;
                end

                // ---------------------------------------------------------
                // LAYER phase: read out acc[tile_cnt] from both tiles
                // ---------------------------------------------------------
                S_ISSUE_LAYER: begin
                    mode           <= MODE_LAYER;
                    start_layering <= 1'b1;
                    state          <= S_WAIT_LAY_ON;
                end

                S_WAIT_LAY_ON: begin
                    mode <= MODE_LAYER;
                    if (layer_ctrl_busy)
                        state <= S_WAIT_LAY_OFF;
                end

                S_WAIT_LAY_OFF: begin
                    mode <= MODE_LAYER;
                    if (!layer_ctrl_busy)
                        state <= S_NEXT_TILE;
                end

                // ---------------------------------------------------------
                // Advance to next row tile or finish
                // ---------------------------------------------------------
                S_NEXT_TILE: begin
                    if (tile_cnt == NUM_TILES - 1) begin
                        state <= S_IDLE;
                        done  <= 1'b1;
                    end else begin
                        tile_cnt <= tile_cnt + 1;
                        row_tile <= tile_cnt + 1;
                        state    <= S_ISSUE_LOAD;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule