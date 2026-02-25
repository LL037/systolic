
module top_ctrl_nn #(
    parameter N = 4   // Matrix dimension (must be divisible by 4)
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       start,

    // Handshakes from sub-controllers
    input  wire       valid_ctrl_busy,
    input  wire       layer_ctrl_busy,
    input  wire       next_tile_ready,

    output reg                    next_tile,     
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
        S_IDLE           = 4'd0,
        S_ISSUE_LOAD     = 4'd1,
        S_WAIT_LOAD_ON   = 4'd2,
        S_WAIT_LOAD_OFF  = 4'd3,
        S_NEXT_LOAD_TILE = 4'd4,
        S_ISSUE_LAYER    = 4'd5,
        S_WAIT_LAY_ON    = 4'd6,
        S_WAIT_LAY_OFF   = 4'd7,
        S_NEXT_LAY_TILE  = 4'd8,
        S_DONE           = 4'd9;

    reg [3:0] state;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state                <= S_IDLE;
            mode                 <= MODE_IDLE;
            start_valid_pipeline <= 1'b0;
            start_layering       <= 1'b0;
            start_weights        <= 1'b0;
            start_input          <= 1'b0;
            done                 <= 1'b0;
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
                    mode          <= MODE_IDLE;
        
                    if (start && !valid_ctrl_busy && !layer_ctrl_busy)
                        state <= S_ISSUE_LOAD;
                end
                // loading
                S_ISSUE_LOAD: begin
                    mode                 <= MODE_LOAD;
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
                    if (!valid_ctrl_busy && next_tile_ready)
                        state <= S_NEXT_LOAD_TILE;
                end
                // next tile 
                S_NEXT_LOAD_TILE: begin
                    mode <= MODE_LOAD;
                    if (!valid_ctrl_busy)
                        state <= S_ISSUE_LOAD;
                    end
                end

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
                        state <= S_DONE;
                end


                // ---------------------------------------------------------
                S_DONE: begin
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule