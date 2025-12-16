module top_ctrl(
    input  wire       clk,
    input  wire       rst,
    input  wire       start,

    input  wire       valid_ctrl_busy,
    input  wire       layer_ctrl_busy,

    output reg  [2:0] mode,
    output reg        start_valid_pipeline,
    output reg        start_layering,
    output reg        start_weights,
    output reg        start_input
);

    localparam [2:0] MODE_IDLE  = 3'd0;
    localparam [2:0] MODE_LOAD  = 3'd1;
    localparam [2:0] MODE_LAYER = 3'd2;

    localparam [2:0]
        S_IDLE          = 3'd0,
        S_ISSUE_LOAD    = 3'd1,
        S_WAIT_LOAD_ON  = 3'd2,
        S_WAIT_LOAD_OFF = 3'd3,
        S_ISSUE_LAYER   = 3'd4,
        S_WAIT_LAY_ON   = 3'd5,
        S_WAIT_LAY_OFF  = 3'd6;

    reg [2:0] state;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
            mode  <= MODE_IDLE;

            start_valid_pipeline <= 1'b0;
            start_layering       <= 1'b0;
            start_weights        <= 1'b0;
            start_input          <= 1'b0;
        end else begin
            // default: 1-cycle pulses
            start_valid_pipeline <= 1'b0;
            start_layering       <= 1'b0;
            start_weights        <= 1'b0;
            start_input          <= 1'b0;

            case (state)
                S_IDLE: begin
                    mode <= MODE_IDLE;
                    if (start && !valid_ctrl_busy && !layer_ctrl_busy) begin
                        state <= S_ISSUE_LOAD;
                    end
                end

                // ---------- LOAD phase ----------
                S_ISSUE_LOAD: begin
                    mode <= MODE_LOAD;
                    start_weights        <= 1'b1;
                    start_input          <= 1'b1;
                    start_valid_pipeline <= 1'b1;
                    state <= S_WAIT_LOAD_ON;
                end

                S_WAIT_LOAD_ON: begin
                    mode <= MODE_LOAD;
                    if (valid_ctrl_busy)
                        state <= S_WAIT_LOAD_OFF; // ACK
                end

                S_WAIT_LOAD_OFF: begin
                    mode <= MODE_LOAD;
                    if (!valid_ctrl_busy)
                        state <= S_ISSUE_LAYER;   // DONE
                end

                // ---------- LAYER phase ----------
                S_ISSUE_LAYER: begin
                    mode <= MODE_LAYER;
                    start_layering <= 1'b1;
                    state <= S_WAIT_LAY_ON;
                end

                S_WAIT_LAY_ON: begin
                    mode <= MODE_LAYER;
                    if (layer_ctrl_busy)
                        state <= S_WAIT_LAY_OFF;  // ACK
                end

                S_WAIT_LAY_OFF: begin
                    mode <= MODE_LAYER;
                    if (!layer_ctrl_busy)
                        state <= S_IDLE;          // DONE
                end

                default: begin
                    state <= S_IDLE;
                    mode  <= MODE_IDLE;
                end
            endcase
        end
    end

endmodule
