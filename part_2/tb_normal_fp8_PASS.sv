`timescale 1ns/1ns
module matmul_tb;

    logic clk;
    logic resetn;
    logic pe_resetn;
    logic start;
    logic done;
    logic [4:0] exception_flags;

    //DUT
    matrix_multiplication u_matmul(
        .clk(clk), 
        .resetn(resetn), 
        .pe_resetn(pe_resetn), 
        .address_mat_a(10'b0),
        .address_mat_b(10'b0),
        .address_mat_c(10'b0),
        .address_stride_a(8'd1),
        .address_stride_b(8'd1),
        .address_stride_c(8'd1),
        
        // External RAM ports are unused in this testbench.
        .bram_addr_a_ext('0),
        .bram_rdata_a_ext(),
        .bram_wdata_a_ext('0),
        .bram_we_a_ext('0),

        .bram_addr_b_ext('0),
        .bram_rdata_b_ext(),
        .bram_wdata_b_ext('0),
        .bram_we_b_ext('0),

        .bram_addr_c_ext('0),
        .bram_rdata_c_ext(),
        .bram_wdata_c_ext('0),
        .bram_we_c_ext('0),

        .start(start),
	    .done(done),
        .exception_flags(exception_flags)
        );
    
    //Clock Generation  
    initial 
    begin
        clk = 0;
        forever 
        begin
            #10 clk = ~clk;
        end
    end
    
    //Reset
    initial 
    begin
        resetn = 0;
        pe_resetn = 0;
        #55;
        resetn = 1;
        pe_resetn = 1;
    end
    
//////////////////////////////////////////////////////////////////////////
// Start multiplication and verify normal FP8 test
//////////////////////////////////////////////////////////////////////////
initial begin
    start = 0;

    // Wait until reset has been released.
    wait (resetn == 1'b1 && pe_resetn == 1'b1);

    // Start on a falling edge to avoid races with the DUT.
    @(negedge clk);
    start = 1'b1;

    @(negedge clk);
    start = 1'b0;

    // Wait for matrix multiplication to complete.
    @(posedge done);

    // Allow final RAM write to complete.
    repeat (2) @(posedge clk);

$display("--------------------------------------------------");
$display("FP8 MATRIX MULTIPLICATION - NORMAL MATRIX TEST");
$display("C RAM[0] = %h  Expected = 38513444",
         u_matmul.matrix_C.ram[0]);
$display("C RAM[1] = %h  Expected = 4448444A",
         u_matmul.matrix_C.ram[1]);
$display("C RAM[2] = %h  Expected = 304A4246",
         u_matmul.matrix_C.ram[2]);
$display("C RAM[3] = %h  Expected = 4C514250",
         u_matmul.matrix_C.ram[3]);
$display("exception_flags = %b", exception_flags);
$display("--------------------------------------------------");

if ((u_matmul.matrix_C.ram[0] === 32'h38513444) &&
    (u_matmul.matrix_C.ram[1] === 32'h4448444A) &&
    (u_matmul.matrix_C.ram[2] === 32'h304A4246) &&
    (u_matmul.matrix_C.ram[3] === 32'h4C514250) &&
    (exception_flags === 5'b00000)) begin

    $display("NORMAL FP8 MATRIX TEST PASSED");
end
else begin
    $display("NORMAL FP8 MATRIX TEST FAILED");
end

    #40;
    $finish;
end
    

//////////////////////////////////////////////////////////////////////////
// Normal FP8 Test
//
// FP8 values used:
// 0.0 = 8'h00
// 0.5 = 8'h20
// 1.0 = 8'h30
// 1.5 = 8'h38
// 2.0 = 8'h40
//
// Matrix A:
// [1.0  0.5  2.0  1.0]
// [0.5  1.0  1.5  0.0]
// [2.0  1.0  0.5  1.5]
// [1.5  0.0  1.0  0.5]
//
// Matrix B:
// [0.5  1.0  0.0  1.5]
// [1.0  0.5  1.5  0.0]
// [0.0  1.0  0.5  1.0]
// [1.5  0.0  1.0  0.5]
//////////////////////////////////////////////////////////////////////////

initial begin

    // Matrix A:
    // Each RAM address contains one column of A.
    // The row-0 element is stored in the least-significant byte.
    u_matmul.matrix_A.ram[0] = 32'h38402030;
    u_matmul.matrix_A.ram[1] = 32'h00303020;
    u_matmul.matrix_A.ram[2] = 32'h30203840;
    u_matmul.matrix_A.ram[3] = 32'h20380030;

    // Matrix B:
    // Each RAM address contains one row of B.
    // The column-0 element is stored in the least-significant byte.
    u_matmul.matrix_B.ram[0] = 32'h38003020;
    u_matmul.matrix_B.ram[1] = 32'h00382030;
    u_matmul.matrix_B.ram[2] = 32'h30203000;
    u_matmul.matrix_B.ram[3] = 32'h20300038;

end

initial begin
    $fsdbDumpfile("normal_fp8.fsdb");
    $fsdbDumpvars(0, matmul_tb, "+all");
    $fsdbDumpMDA();
end

endmodule
