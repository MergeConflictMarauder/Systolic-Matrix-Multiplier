`timescale 1ns/1ns
module matmul_tb;

    logic clk;
    logic resetn;
    logic pe_resetn;
    logic start;
    logic done;
    logic [4:0] exception_flags;
    logic exception_seen;

    // Remember if any FP8 exception occurs during the matrix multiplication.
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn)
            exception_seen <= 1'b0;
        else if (exception_flags != 5'b00000)
            exception_seen <= 1'b1;
    end

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
// Start multiplication and verify exception FP8 test
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
    $display("FP8 MATRIX MULTIPLICATION - EXCEPTION TEST");

    $display("C RAM[0] = %h  Expected = 50000070",
             u_matmul.matrix_C.ram[0]);
    $display("C RAM[1] = %h  Expected = 00203430",
             u_matmul.matrix_C.ram[1]);
    $display("C RAM[2] = %h  Expected = 20383830",
             u_matmul.matrix_C.ram[2]);
    $display("C RAM[3] = %h  Expected = 30300000",
             u_matmul.matrix_C.ram[3]);

    $display("exception_flags now = %b", exception_flags);
    $display("exception_seen      = %b", exception_seen);
    $display("--------------------------------------------------");

    if ((u_matmul.matrix_C.ram[0] === 32'h50000070) &&
        (u_matmul.matrix_C.ram[1] === 32'h00203430) &&
        (u_matmul.matrix_C.ram[2] === 32'h20383830) &&
        (u_matmul.matrix_C.ram[3] === 32'h30300000) &&
        (exception_seen === 1'b1)) begin

        $display("EXCEPTION FP8 MATRIX TEST PASSED");
    end
    else begin
        $display("EXCEPTION FP8 MATRIX TEST FAILED");
    end

    #40;
    $finish;
end


//////////////////////////////////////////////////////////////////////////
// FP8 Exception Test
//
// This test intentionally includes an 8.0 x 8.0 multiplication.
// The result exceeds the finite range of FP8 e3m4, causing overflow.
//
// Expected behavior:
// - At least one exception flag is asserted during computation.
// - exception_seen becomes 1.
// - C[0][0] becomes +Infinity (FP8 8'h70).
//////////////////////////////////////////////////////////////////////////

initial begin

    // Exception test:
    // Contains 8.0 x 8.0, which overflows FP8 e3m4.

    // Matrix A - stored by columns
    u_matmul.matrix_A.ram[0] = 32'h20000060;
    u_matmul.matrix_A.ram[1] = 32'h00003030;
    u_matmul.matrix_A.ram[2] = 32'h00302000;
    u_matmul.matrix_A.ram[3] = 32'h30300000;

    // Matrix B - stored by rows
    u_matmul.matrix_B.ram[0] = 32'h00000060;
    u_matmul.matrix_B.ram[1] = 32'h00303000;
    u_matmul.matrix_B.ram[2] = 32'h00302000;
    u_matmul.matrix_B.ram[3] = 32'h30200000;

end

initial begin
    $fsdbDumpfile("exception_fp8.fsdb");
    $fsdbDumpvars(0, matmul_tb, "+all");
    $fsdbDumpMDA();
end

endmodule
