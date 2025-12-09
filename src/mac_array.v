module mac_array #(
    parameter W      = 8,  
    parameter ACC_W  = 16,
    parameter N_MACS = 4
)(
    input  wire                    clk,
    input  wire                    rst,
    
    // Control signals for each MAC
    input  wire [N_MACS-1:0]       valid_in_0,  
    input  wire [N_MACS-1:0]       valid_in_1, 
    input  wire [N_MACS-1:0]       valid_in_2,   
  
 
    input  wire [N_MACS-1:0]       clear,      
    
    // Single activation input (flows through the array)
    input  wire signed [ACC_W-1:0]     a_in,
    
    // Weight inputs for each MAC
    input  wire signed [ACC_W-1:0]     w_0,        // Weight for MAC 0
    input  wire signed [ACC_W-1:0]     w_1,        // Weight for MAC 1
    input  wire signed [ACC_W-1:0]     w_2,        // Weight for MAC 2
    input  wire signed [ACC_W-1:0]     w_3,        // Weight for MAC 3
    
    // Final outputs
    output wire signed [ACC_W-1:0] acc_out_0,
    output wire signed [ACC_W-1:0] acc_out_1,
    output wire signed [ACC_W-1:0] acc_out_2,
    output wire signed [ACC_W-1:0] acc_out_3,
    output wire [N_MACS-1:0]       valid_out
);

    wire signed [ACC_W-1:0]     a_out_0_1;
    wire signed [ACC_W-1:0]     a_out_0_1_1;

    wire signed [ACC_W-1:0]     a_out_1_0;  
    wire signed [ACC_W-1:0]     a_out_2_3;  
    wire signed [ACC_W-1:0]     a_out_3_2;  


    // MAC 0 (top-left)
    mac #(
        .W(W),
        .ACC_W(ACC_W)
    ) mac_0 (
        .clk(clk),
        .rst(rst),
        .acc_sel(3'b000),
        .valid_in_0(valid_in_0[0]),
        .valid_in_1(valid_in_1[0]),
        .valid_in_2(valid_in_2[0]),
        .clear(clear[0]),
        .a_in_0(a_in),
        .a_in_1(acc_out_2),
        .a_in_2(a_out_1_0),              
        .weight(w_0),               
        .acc_out(acc_out_0),
        .valid_out(valid_out[0]),
        .a_out_0(a_out_0_1),
        .a_out_1(a_out_0_1_1),
        .a_out_2()        
    );

    // MAC 1 (top-right)
    mac #(
        .W(W),
        .ACC_W(ACC_W)
    ) mac_1 (
        .clk(clk),
        .rst(rst),
        .acc_sel(3'b000),
        .valid_in_0(valid_in_0[1]),
        .valid_in_1(valid_in_1[1]),
        .valid_in_2(valid_in_2[1]),
        .clear(clear[1]),
        .a_in_0(a_out_0_1),
        .a_in_1(a_out_0_1_1),   
        .a_in_2(acc_out_3),            
        .weight(w_1),               
        .acc_out(acc_out_1),
        .valid_out(valid_out[1]),
        .a_out_0(),
        .a_out_1(),
        .a_out_2(a_out_1_0)        
    );

    // MAC 2 (bottom-left)
    mac #(
        .W(W),
        .ACC_W(ACC_W)
    ) mac_2 (
        .clk(clk),
        .rst(rst),
        .acc_sel(3'b000),
        .valid_in_0(valid_in_0[2]),
        .valid_in_1(valid_in_1[2]),
        .valid_in_2(valid_in_2[2]),
        .clear(clear[2]),
        .a_in_0(acc_out_0),
        .a_in_1(a_out_3_2),
        .a_in_2(),                
        .weight(w_2),               
        .acc_out(acc_out_2),
        .valid_out(valid_out[2]),
        .a_out_0(a_out_2_3),
        .a_out_1(), 
        .a_out_2()        
       
    );
    // MAC 3 (bottom-right)
    mac #(
        .W(W),
        .ACC_W(ACC_W)
    ) mac_3 (
        .clk(clk),
        .rst(rst),
        .acc_sel(3'b000),
        .valid_in_0(valid_in_0[3]),
        .valid_in_1(valid_in_1[3]),
        .valid_in_2(valid_in_2[3]),
        .clear(clear[3]),
        .a_in_0(acc_out_1),
        .a_in_1(a_out_2_3), 
        .a_in_2(),             
        .weight(w_3),               
        .acc_out(acc_out_3),
        .valid_out(valid_out[3]),
        .a_out_0(a_out_3_2),
        .a_out_1(),  
        .a_out_2()        

    );

endmodule
