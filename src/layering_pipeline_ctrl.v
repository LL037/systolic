// layering_pipeline_ctrl_nn.v
// Layer phase: reads acc[tile_idx] from tile1 (y[2t], y[2t+1])
//              and acc[tile_idx] from tile2 (y[2t+2], y[2t+3])
// Two clock cycles: S_LOAD0 sends tile1 outputs, S_SWAP0 sends tile2 outputs.
// (Same two-state machine as original, retained for compatibility)

module layering_pipeline_ctrl_nn (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire        layer_ready,
    output reg  [11:0] valid_ctrl,
    output reg         busy
);
    localparam IDLE   = 2'd0;
    localparam S_WAIT = 2'd1;
    localparam S_LOAD0= 2'd2;
    localparam S_SWAP0= 2'd3;

    reg [1:0] state, next_state;

    always @(posedge clk) begin
        if (rst)  state <= IDLE;
        else      state <= next_state;
    end

    always @(*) begin
        next_state = state;
        case (state)
            IDLE:    next_state = start       ? S_WAIT  : IDLE;
            S_WAIT:  next_state = layer_ready ? S_LOAD0 : S_WAIT;
            S_LOAD0: next_state = S_SWAP0;
            S_SWAP0: next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    // valid_ctrl: drive mac_0/mac_1 with a_in_1 (acc feedback) in S_LOAD0
    //             drive mac_2/mac_3 with a_in_1 in S_SWAP0
    always @(*) begin
        case (state)
            S_LOAD0: valid_ctrl = 12'b001001000000; // mac_0 a_in_1, mac_1 a_in_1
            S_SWAP0: valid_ctrl = 12'b010010000000; // mac_2 a_in_1, mac_3 a_in_1
            default: valid_ctrl = 12'b000000000000;
        endcase
    end

    always @(posedge clk) begin
        if (rst) busy <= 1'b0;
        else     busy <= (next_state != IDLE);
    end

endmodule