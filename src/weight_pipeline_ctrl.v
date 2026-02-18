// weight_pipeline_ctrl_nn.v
// Extends original weight_pipeline_ctrl to support arbitrary N.
// In LOAD mode:  mac_0/mac_1 weight_valid active (bits [1:0])
//                mac_2/mac_3 weight_valid active (bits [3:2])
//                All 4 MACs accept weights simultaneously (one row of W per cycle)
// In LAYER mode: no weights needed (acc readout only)

module weight_pipeline_ctrl_nn #(
    parameter N_MACS = 4
)(
    input  wire         clk,
    input  wire         rst,
    input  wire         start,
    input  wire [2:0]   mode,       // 0:idle 1:load 2:layer

    output reg  [N_MACS-1:0] weight_ctrl,
    output reg  [2:0]        load,
    output reg               busy,
    output reg               load_ready,
    output reg               layer_ready
);
    localparam IDLE  = 2'd0;
    localparam LOAD  = 2'd1;
    localparam LAYER = 2'd2;

    reg [1:0] state, next_state;
    reg [2:0] prev_mode;
    reg [2:0] load_pulse;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state      <= IDLE;
            prev_mode  <= 3'd0;
            load_pulse <= 3'b000;
        end else begin
            state      <= next_state;
            load_pulse <= 3'b000;
            if (mode != prev_mode) begin
                if      (mode == 3'd1) load_pulse <= 3'b001;
                else if (mode == 3'd2) load_pulse <= 3'b010;
            end
            prev_mode <= mode;
        end
    end

    always @(*) begin
        next_state = state;
        if (mode == 3'd0)          next_state = IDLE;
        else if (mode != prev_mode) begin
            case (mode)
                3'd1:    next_state = LOAD;
                3'd2:    next_state = LAYER;
                default: next_state = state;
            endcase
        end
    end

    always @(*) begin
        weight_ctrl = {N_MACS{1'b0}};
        busy        = 1'b0;
        load_ready  = 1'b0;
        layer_ready = 1'b0;
        load        = load_pulse;
        case (state)
            LOAD:  begin
                weight_ctrl = {N_MACS{1'b1}};  // all 4 MACs receive weights
                load_ready  = 1'b1;
                busy        = 1'b1;
            end
            LAYER: begin
                weight_ctrl = {N_MACS{1'b0}};  // no weights during readout
                layer_ready = 1'b1;
                busy        = 1'b1;
            end
            default: ;
        endcase
    end

endmodule