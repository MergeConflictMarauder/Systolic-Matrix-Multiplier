`timescale 1ns/1ps

//////////////////////////////////////////////////////////////////////////
// Testbench for the 8x8 FP8 matrix multiplier with the APB interface (part 4).
// The testbench plays the CPU: it controls the matmul only through APB
// register writes and reads, using the write/read tasks from example_tb.v.
// The CPU writes the addresses and strides, writes START, polls DONE, then
// reads FLAGS. The RAMs are loaded and C is checked hierarchically, as in
// part 3, against expected values worked out by hand.
//   +TEST=ones       A and B all 1.0, so every element of C is 8.0 (8'h60)
//                    and FLAGS is 00000.
//   +TEST=exception  A and B all 1.0 except A[0][0] = B[0][0] = 8.0 (default).
//                    8.0 x 8.0 = 64 overflows FP8, so C[0][0] is +inf (8'h70)
//                    and FLAGS is 10001 (Overflow, Inexact).
// Both tests place A, B and C at nonzero addresses with strides 1, 2 and 3.
// Reports PASS/FAIL. Define FSDB_DUMP to write <test>_apb.fsdb for Verdi.
//////////////////////////////////////////////////////////////////////////
module matmul_apb_tb;

    reg                         clk;
    reg                         reset;          // Active high, as in example_tb.v
    reg  [`REG_ADDRWIDTH-1:0]   PADDR;
    reg                         PWRITE;
    reg                         PSEL;
    reg                         PENABLE;
    reg  [`REG_DATAWIDTH-1:0]   PWDATA;
    wire [`REG_DATAWIDTH-1:0]   PRDATA;
    wire                        PREADY;

    localparam T_ONES = 0, T_EXCEPTION = 1;

    integer          test_id;
    reg [8*16-1:0]   test_name;

    reg  [`REG_DATAWIDTH-1:0] rdata;            // Last value read over APB
    reg  [4:0]  flags_read;                     // FLAGS register read after DONE
    reg         done;
    integer     polls;

    // Matrices, expected results, the register values the CPU programs
    // (addr_*, stride_*) and the shared load/check tasks
    // (shared with part_3, see ../matmul_8x8_test_utils.vh)
`include "matmul_8x8_test_utils.vh"

    //////////////////////////////////////////////////////////////////////
    // DUT
    //////////////////////////////////////////////////////////////////////
    matrix_multiplication_8x8_apb u_matmul (
        .PCLK     (clk),
        .PRESETn  (~reset),
        .PADDR    (PADDR),
        .PWRITE   (PWRITE),
        .PSEL     (PSEL),
        .PENABLE  (PENABLE),
        .PWDATA   (PWDATA),
        .PRDATA   (PRDATA),
        .PREADY   (PREADY),

        // External RAM ports are unused: the RAMs are loaded and read hierarchically
        .bram_addr_a0_ext (10'b0), .bram_wdata_a0_ext(32'b0), .bram_we_a0_ext(4'b0), .bram_rdata_a0_ext(),
        .bram_addr_a1_ext (10'b0), .bram_wdata_a1_ext(32'b0), .bram_we_a1_ext(4'b0), .bram_rdata_a1_ext(),
        .bram_addr_b0_ext (10'b0), .bram_wdata_b0_ext(32'b0), .bram_we_b0_ext(4'b0), .bram_rdata_b0_ext(),
        .bram_addr_b1_ext (10'b0), .bram_wdata_b1_ext(32'b0), .bram_we_b1_ext(4'b0), .bram_rdata_b1_ext(),
        .bram_addr_c0_ext (10'b0), .bram_wdata_c0_ext(32'b0), .bram_we_c0_ext(4'b0), .bram_rdata_c0_ext(),
        .bram_addr_c1_ext (10'b0), .bram_wdata_c1_ext(32'b0), .bram_we_c1_ext(4'b0), .bram_rdata_c1_ext()
    );

    //////////////////////////////////////////////////////////////////////
    // Clock generation (20 ns period)
    //////////////////////////////////////////////////////////////////////
    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;
    end

    //////////////////////////////////////////////////////////////////////
    // APB write and read tasks, as provided in example_tb.v
    //////////////////////////////////////////////////////////////////////
    // Task to write into the configuration block of the DUT
    task write(input [`REG_ADDRWIDTH-1:0] addr, input [`REG_DATAWIDTH-1:0] data);
        begin
            @(negedge clk);
            PSEL   = 1;
            PWRITE = 1;
            PADDR  = addr;
            PWDATA = data;
            @(negedge clk);
            PENABLE = 1;
            @(negedge clk);
            PSEL    = 0;
            PENABLE = 0;
            PWRITE  = 0;
            PADDR   = 0;
            PWDATA  = 0;
            $display("%t: PADDR %h, PWDATA %h", $time, addr, data);
        end
    endtask

    // Task to read from the configuration block of the DUT
    task read(input [`REG_ADDRWIDTH-1:0] addr, output [`REG_DATAWIDTH-1:0] data);
        begin
            @(negedge clk);
            PSEL   = 1;
            PWRITE = 0;
            PADDR  = addr;
            @(negedge clk);
            PENABLE = 1;
            @(negedge clk);
            PSEL    = 0;
            PENABLE = 0;
            data    = PRDATA;
            PADDR   = 0;
            $display("%t: PADDR %h, PRDATA %h", $time, addr, data);
        end
    endtask

    //////////////////////////////////////////////////////////////////////
    // Test matrices, register values and the expected result
    //   ones:      every element of C is 8 x (1.0 x 1.0) = 8.0 (8'h60), exact.
    //   exception: A[0][0] = B[0][0] = 8.0, everything else 1.0.
    //              C[0][0]            = 8.0 x 8.0 + 7 x 1.0 = +inf (8'h70):
    //                                   64 overflows FP8 before the sum
    //              rest of row/col 0  = 8.0 x 1.0 + 7 x 1.0 = 15.0 (8'h6E)
    //              all other elements = 8.0 (8'h60)
    //////////////////////////////////////////////////////////////////////
    task set_test;
        integer i, j;
        begin
            for (i = 0; i < 8; i = i + 1) begin
                for (j = 0; j < 8; j = j + 1) begin
                    mat_a[i][j] = 8'h30;        // 1.0
                    mat_b[i][j] = 8'h30;
                    exp_c[i][j] = 8'h60;        // 8.0
                end
            end
            exp_flags = 5'b00000;

            if (test_id == T_EXCEPTION) begin
                mat_a[0][0] = 8'h60;            // 8.0
                mat_b[0][0] = 8'h60;
                for (i = 1; i < 8; i = i + 1) begin
                    exp_c[0][i] = 8'h6E;        // 15.0
                    exp_c[i][0] = 8'h6E;
                end
                exp_c[0][0] = 8'h70;            // +inf
                exp_flags   = 5'b10001;         // Overflow, Inexact
            end

            addr_a = 10'd16;  stride_a = 8'd1;
            addr_b = 10'd32;  stride_b = 8'd2;
            addr_c = 10'd64;  stride_c = 8'd3;
        end
    endtask

    //////////////////////////////////////////////////////////////////////
    // CPU flow: 1) write addresses/strides, 2) write START,
    // 3) poll DONE, 4) read FLAGS
    //////////////////////////////////////////////////////////////////////
    task run_cpu_flow;
        begin
            $display("Write the addresses and strides");
            write(`REG_MATA_ADDR, addr_a);
            write(`REG_MATB_ADDR, addr_b);
            write(`REG_MATC_ADDR, addr_c);
            write(`REG_STRA_ADDR, stride_a);
            write(`REG_STRB_ADDR, stride_b);
            write(`REG_STRC_ADDR, stride_c);

            $display("Start the matmul");
            write(`REG_STRT_ADDR, 16'h0001);

            $display("Wait until done");
            polls = 0;
            do begin
                read(`REG_DONE_ADDR, rdata);
                done  = rdata[15];
                polls = polls + 1;
            end while (done == 0);
            $display("DONE after %0d polls", polls);

            $display("Read the flags");
            read(`REG_FLAG_ADDR, rdata);
            flags_read = rdata[4:0];
            runs = runs + 1;
        end
    endtask

    //////////////////////////////////////////////////////////////////////
    // Compare C in RAM and the FLAGS read over APB with the expected values
    //////////////////////////////////////////////////////////////////////
    task check_result;
        begin
            check_c(1'b1);
            $display("FLAGS read over APB = %b, expected %b", flags_read, exp_flags);
            check_flags(flags_read);
        end
    endtask

    task write_test_name;
        if (test_id == T_ONES) $write("ones");
        else                   $write("exception");
    endtask

    //////////////////////////////////////////////////////////////////////
    // Main sequence
    //////////////////////////////////////////////////////////////////////
    initial begin
        reset   = 1'b1;
        PSEL    = 0;
        PENABLE = 0;
        PWRITE  = 0;
        PADDR   = 0;
        PWDATA  = 0;
        runs    = 0;
        errors  = 0;

        if (!$value$plusargs("TEST=%s", test_name)) test_name = "exception";

        if      (test_name == "ones")      test_id = T_ONES;
        else if (test_name == "exception") test_id = T_EXCEPTION;
        else begin
            $display("FAIL: unknown test, use +TEST=ones or exception");
            $finish;
        end

`ifdef FSDB_DUMP
        if (test_id == T_ONES) $fsdbDumpfile("ones_apb.fsdb");
        else                   $fsdbDumpfile("exception_apb.fsdb");
        $fsdbDumpvars(0, matmul_apb_tb, "+all");
        $fsdbDumpMDA;
`endif

        $display("--------------------------------------------------");
        $write("8x8 FP8 MATRIX MULTIPLICATION OVER APB - TEST: ");
        write_test_name;
        $display("");

        // Bring the design out of reset, then wait a couple of clocks
        repeat (5) @(negedge clk);
        reset = 1'b0;
        repeat (2) @(negedge clk);

        set_test;
        load_rams;
        run_cpu_flow;
        check_result;

        $display("%0d mismatches, FLAGS = %b", errors, flags_read);
        $display("--------------------------------------------------");
        if (errors == 0 && runs > 0) $write("PASS: ");
        else                         $write("FAIL: ");
        write_test_name;
        $display("");

        // A little bit of drain time before we finish
        #200;
        $finish;
    end

    // Guard against a design that never sets DONE
    initial begin
        #1_000_000;
        $display("FAIL: timeout, DONE was not set");
        $finish;
    end

endmodule
