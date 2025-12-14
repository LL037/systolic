module weight_pipeline_ctrl #(
    parameter N_MACS = 4

)(
    input  wire       clk,
    input  wire       rst,
    input  wire       start,

    input  wire [2:0]      mode, // 0: idle, 1: load weights, 2: layering
    output reg  [N_MACS-1:0] weight_ctrl, 
    output reg        busy        
);
// FSM states
localparam IDLE  = 2'd0;
localparam LOAD  = 2'd1;
localparam LAYER = 2'd2;

// masks for N_MACS (for N_MACS==4 yields 4'b0011 and 4'b1100)
localparam integer HALF_W = N_MACS / 2;
localparam [N_MACS-1:0] LOAD_MASK  = ((1 << HALF_W) - 1);
localparam [N_MACS-1:0] LAYER_MASK = (LOAD_MASK << HALF_W);

reg [1:0] state, next_state;
reg [2:0] prev_mode;

// state register and remember previous mode
always @(posedge clk or posedge rst) begin
    if (rst) begin
        state     <= IDLE;
        prev_mode <= 3'd0;
    end else begin
        state     <= next_state;
        prev_mode <= mode;
    end
end
// next state logic
always @(*) begin
    next_state = state;
    if (mode == 3'd0) begin
        next_state = IDLE;
    end else if (mode != prev_mode) begin
        case (mode)
            3'd1: next_state = LOAD;
            3'd2: next_state = LAYER;
            default: next_state = state;
        endcase
    end
end

// outputs based on current state
always @(*) begin
    case (state)
        IDLE: begin
            weight_ctrl = {N_MACS{1'b0}};
            busy        = 1'b0;
        end
        LOAD: begin
            weight_ctrl = LOAD_MASK;   // 4'b0011 
            busy        = 1'b1;
        end
        LAYER: begin
            weight_ctrl = LAYER_MASK;  //  4'b1100 
            busy        = 1'b1;
        end
        default: begin
            weight_ctrl = {N_MACS{1'b0}};
            busy        = 1'b0;
        end
    endcase
end

endmodule



