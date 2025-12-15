module top_ctrl(
    input  wire       clk,
    input  wire       rst,
    input  wire       start,

    output reg  [2:0] mode,
    output reg        start_valid_pipeline,
    output reg        start_layering,
    
    output reg        start_weights,
    output reg        start_input
);

    // mode encoding (match your weight_pipeline_ctrl expectation)
    localparam [2:0] MODE_IDLE  = 3'd0;
    localparam [2:0] MODE_LOAD  = 3'd1;
    localparam [2:0] MODE_LAYER = 3'd2;

    // simple sequencer:
    // 1) kick weights + input + valid pipeline (load phase)
    // 2) kick layering (layer phase)
    // pulses are 1-cycle wide
    localparam [1:0] S_IDLE  = 2'd0;
    localparam [1:0] S_LOAD  = 2'd1;
    localparam [1:0] S_LAYER = 2'd2;

    reg [1:0] state;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;

            mode <= MODE_IDLE;

            start_valid_pipeline <= 1'b0;
            start_layering       <= 1'b0;
            start_weights        <= 1'b0;
            start_input          <= 1'b0;
        end else begin
            // default: deassert pulses
            start_valid_pipeline <= 1'b0;
            start_layering       <= 1'b0;
            start_weights        <= 1'b0;
            start_input          <= 1'b0;

            case (state)
                S_IDLE: begin
                    mode <= MODE_IDLE;
                    if (start) begin
                        state <= S_LOAD;

                        mode <= MODE_LOAD;
                        start_weights        <= 1'b1;
                        start_input          <= 1'b1;
                        start_valid_pipeline <= 1'b1;
                    end
                end

                S_LOAD: begin
                    // one-cycle kick already issued; move on
                    state <= S_LAYER;

                    mode <= MODE_LAYER;
                    start_layering <= 1'b1;
                end

                S_LAYER: begin
                    // done; stay idle until next start
                    state <= S_IDLE;
                    mode  <= MODE_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                    mode  <= MODE_IDLE;
                end
            endcase
        end
    end

endmodule
