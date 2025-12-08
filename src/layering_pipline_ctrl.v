module layering_pipeline_ctrl (
    input  wire       clk,
    input  wire       rst,
    input  wire       start,
    output reg  [3:0] valid_ctrl,
    output reg        busy
);
    localparam IDLE   = 4'd0;
    localparam S_LOAD0= 4'd1; // 第1拍: 接上一层acc
    localparam S_MAC0 = 4'd2; // 第2拍: 算MAC
    localparam S_SWAP0= 4'd3; // 第3拍: 交换
    localparam S_MAC1 = 4'd4; // 第4拍: 算MAC
    localparam S_LOAD1= 4'd5; // 第5拍: 接新acc
    localparam S_MAC2 = 4'd6; // 第6拍: 算MAC
    localparam S_SWAP1= 4'd7; // 第7拍: 交换
    localparam S_MAC3 = 4'd8; // 第8拍: 算MAC

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
        valid_ctrl = 4'b0000;
        case (state)
            // 第1拍: M2,M3 接上一层acc
            S_LOAD0: valid_ctrl = 4'b0011; // [1:0] = 2'b11
            // 第3拍: M2,M3 走交换路径
            S_SWAP0: valid_ctrl = 4'b1100; // [3:2] = 2'b11
            // 第5拍: 再次接新acc
            S_LOAD1: valid_ctrl = 4'b0011;
            // 第7拍: 再次交换
            S_SWAP1: valid_ctrl = 4'b1100;
            default: valid_ctrl = 4'b0000; // 其它拍不发新valid
        endcase
    end

    always @(posedge clk) begin
        if (rst)
            busy <= 1'b0;
        else
            busy <= (next_state != IDLE);
    end

endmodule
