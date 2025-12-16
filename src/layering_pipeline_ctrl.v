module layering_pipeline_ctrl (
    input  wire       clk,
    input  wire       rst,
    input  wire       start,
    input  wire       layer_ready,   // handshake: only start when ready
    output reg  [11:0] valid_ctrl,
    output reg        busy
);
    localparam IDLE   = 4'd0;
    localparam S_WAIT = 4'd1;   // NEW: wait for layer_ready after start
    localparam S_LOAD0= 4'd2;
    localparam S_SWAP0= 4'd4; 
 
     
    reg [3:0] state, next_state;

    always @(posedge clk) begin
        if (rst)
            state <= IDLE;
        else
            state <= next_state;
    end

    always @(*) begin
        next_state = state;
        case (state)
            IDLE:    next_state = start ? S_WAIT  : IDLE;
            S_WAIT:  next_state = layer_ready ? S_LOAD0 : S_WAIT;

            S_LOAD0: next_state = S_SWAP0;
            S_SWAP0: next_state = IDLE;

            default: next_state = IDLE;
        endcase
    end

    always @(*) begin
        valid_ctrl = 12'b000000000000;
        case (state)
            S_LOAD0: valid_ctrl = 12'b001001000000; 
            S_SWAP0: valid_ctrl = 12'b010010000000;
            default: valid_ctrl = 12'b000000000000;
        endcase
    end

    always @(posedge clk) begin
        if (rst)
            busy <= 1'b0;
        else
            busy <= (next_state != IDLE);
    end

endmodule
