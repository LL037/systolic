module layering_pipeline_ctrl (
    input  wire       clk,
    input  wire       rst,
    input  wire       start,
    output reg  [11:0] valid_ctrl,
    output reg        busy
);
    localparam IDLE   = 4'd0;
    localparam S_LOAD0= 4'd1;
    localparam S_MAC0 = 4'd2; 
    localparam S_SWAP0= 4'd3; 
    localparam S_MAC1 = 4'd4; 
    localparam S_LOAD1= 4'd5; 
    localparam S_MAC2 = 4'd6; 
    localparam S_SWAP1= 4'd7; 
    localparam S_MAC3 = 4'd8; 

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
            IDLE:    next_state = start ? S_LOAD0 : IDLE;
            S_LOAD0: next_state = S_MAC0;
            S_MAC0:  next_state = S_SWAP0;
            S_SWAP0: next_state = S_MAC1;
            S_MAC1:  next_state = S_LOAD1;
            S_LOAD1: next_state = S_MAC2;
            S_MAC2:  next_state = S_SWAP1;
            S_SWAP1: next_state = S_MAC3;
            S_MAC3:  next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    always @(*) begin
        valid_ctrl = 12'b000000000000;
        case (state)
            S_LOAD0: valid_ctrl = 12'b001001000000; 
            S_SWAP0: valid_ctrl = 12'b010010000000;
            S_LOAD1: valid_ctrl = 12'b001001000000;
            S_SWAP1: valid_ctrl = 12'b010010000000;
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
