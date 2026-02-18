// valid_pipeline_ctrl_nn.v
// Generates valid_ctrl for the 2x2 MAC array across N input activations.
//
// For each load phase:
//   - x[0] enters mac_0 on cycle 0,  reaches mac_1 on cycle 1
//   - x[1] enters mac_0 on cycle 1,  reaches mac_1 on cycle 2
//   - ...continues for N cycles
//
// valid_ctrl bit assignment (matches original encoding):
//   bits [2:0]  = mac_0 valid_ctrl  (bit 0 = a_in_0 select)
//   bits [5:3]  = mac_1 valid_ctrl  (bit 0 = a_in_0 select)
//   bits [8:6]  = mac_2 valid_ctrl
//   bits [11:9] = mac_3 valid_ctrl
//
// In load phase:  mac_0 gets a_in_0 directly from input_mem_if
//                 mac_1 gets a_in_0 = mac_0.a_out_0 (1-cycle delayed)
//                 Tile 2 not active during load (weight feed handles it)
// In layer phase: handled by layering_pipeline_ctrl_nn

module valid_pipeline_ctrl_nn #(
    parameter N = 4   // must match matrix size
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,       // 1-cycle pulse to begin
    input  wire        load_ready,  // handshake from weight_mem_if
    output reg  [11:0] valid_ctrl,
    output reg         busy
);

    reg [$clog2(N+2):0] cnt;        // count N cycles of activation
    reg                  running;
    reg                  armed;

    // valid_ctrl encoding for mac_0: bit0=a_in_0
    // valid_ctrl encoding for mac_1: bit0=a_in_0 (= mac_0.a_out_0, 1-cycle late)
    // During load, only tile-1 pair is active (mac_0, mac_1)

    always @(posedge clk) begin
        if (rst) begin
            cnt       <= 0;
            running   <= 1'b0;
            armed     <= 1'b0;
            busy      <= 1'b0;
            valid_ctrl <= 12'd0;
        end else begin
            if (start)  armed <= 1'b1;
            if (load_ready && armed) begin
                running <= 1'b1;
                armed   <= 1'b0;
                cnt     <= 0;
            end

            if (running) begin
                cnt <= cnt + 1;

                // mac_0 active for cycles 0..N-1
                // mac_1 active for cycles 1..N (1 cycle offset due to pass-through)
                // packed: {mac3[2:0], mac2[2:0], mac1[2:0], mac0[2:0]}
                valid_ctrl[2:0]  <= (cnt < N)   ? 3'b001 : 3'b000;  // mac_0 a_in_0
                valid_ctrl[5:3]  <= (cnt > 0 && cnt <= N) ? 3'b001 : 3'b000; // mac_1
                valid_ctrl[11:6] <= 6'b000000;  // tile2 not in load phase

                if (cnt == N + 1) begin
                    running    <= 1'b0;
                    valid_ctrl <= 12'd0;
                end
            end else begin
                valid_ctrl <= 12'd0;
            end

            busy <= running || armed;
        end
    end

endmodule