module valid_pipeline_ctrl (
    input  wire       clk,
    input  wire       rst,
    input  wire       start,
    input  wire       load_ready,
    output reg  [11:0] valid_ctrl, 
    output reg        busy        
);

    reg [5:0] valid_shift;
    reg [1:0] start_tok;   // CHANGED: 2-bit token "11"
    reg       armed;

    always @(posedge clk) begin
        if (rst) begin
            valid_shift <= 6'b000000;
            start_tok   <= 2'b00;
            armed       <= 1'b0;
            busy        <= 1'b0;
        end else begin
            // latch a 2-cycle token on start
            if (start) start_tok <= 2'b11;

            // allow running once ready
            if (load_ready) armed <= 1'b1;

            if (armed || load_ready) begin
                // inject token LSB into tap0 (gives 2 cycles of '1')
                valid_shift[0] <= start_tok[0];
                valid_shift[3] <= valid_shift[0];

                // shift token down (natural decay in 2 cycles)
                start_tok <= {1'b0, start_tok[1]};
            end

            busy <= (|start_tok) | valid_shift[0] | valid_shift[3];

            if (busy == 1'b0)
                armed <= 1'b0;
        end
    end

    always @(*) begin
        valid_ctrl = {3'b000,3'b000,2'b00, valid_shift[3],2'b00, valid_shift[0]};
    end

endmodule

