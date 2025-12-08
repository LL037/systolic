module loading_fsm (
    input  wire       clk,
    input  wire       rst,
    input  wire       start,      // 启动信号，由 testbench 或上层模块给出一个脉冲
    output reg  [3:0] valid_ctrl, // 连接到 mac_array 的 valid_in_0
    output reg        busy        // 状态指示
);


    localparam IDLE   = 3'b001;
    localparam LOAD_0 = 3'b010; // 激活 MAC 0
    localparam LOAD_1 = 3'b100; // 激活 MAC 1

    reg [2:0] current_state, next_state;


    always @(posedge clk) begin
        if (rst) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end


    always @(*) begin
        next_state = current_state;

        case (current_state)
            IDLE: begin
                if (start) 
                    next_state = LOAD_0;
                else       
                    next_state = IDLE;
            end

            LOAD_0: begin
                // 数据流向下一个 MAC，状态机也流向下一个状态
                next_state = LOAD_1; 
            end

            LOAD_1: begin
                // 两个 MAC 处理完毕，结束
                next_state = IDLE; 
            end

            default: next_state = IDLE;
        endcase
    end

    
    always @(posedge clk) begin
        if (rst) begin
            valid_ctrl <= 4'b0000;
            busy       <= 1'b0;
        end else begin
            // 默认全部拉低 (脉冲型控制)
            valid_ctrl <= 4'b0000;
            busy       <= 1'b1;

            case (next_state)
                IDLE: begin
                    busy <= 1'b0;
                end

                LOAD_0: begin
                    // 对应 valid_in_0[0] -> 激活 MAC 0
                    valid_ctrl <= 4'b0001; 
                end

                LOAD_1: begin
                    // 对应 valid_in_0[1] -> 激活 MAC 1
                    // 数据已经从 MAC 0 流到了 MAC 1，所以现在激活 MAC 1
                    valid_ctrl <= 4'b0010; 
                end
                
                default: begin
                    valid_ctrl <= 4'b0000;
                    busy       <= 1'b0;
                end
            endcase
        end
    end

endmodule