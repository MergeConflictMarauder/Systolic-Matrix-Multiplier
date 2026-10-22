`timescale 1ns/1ps

//////////////////////////////////////////////////////////////////////////
// Testbench for the 8x8 FP8 matrix multiplier with the APB interface (part 4).
// The testbench plays the CPU: it controls the matmul only through APB
// register writes and reads, using the write/read tasks from example_tb.v.
// Each run writes the addresses and strides, reads them back, writes START,
// polls DONE, then reads FLAGS and START. The RAMs are loaded and C is
// checked hierarchically, as in part 3, against the FP8 reference model.
//   +TEST=ones       A and B all 1.0, stored at nonzero addresses with strides 1, 2 and 3
//   +TEST=random     5 random matrix pairs back to back, each at its own addresses and strides
//   +TEST=exception  A and B all 1.0 except A[0][0] = B[0][0] = 8.0; 8.0 x 8.0
//                    overflows FP8, so C[0][0] is +inf and the Overflow flag is raised
//   +SEED=<n>        seed for the random test (default 1)
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

    localparam T_ONES = 0, T_RANDOM = 1, T_EXCEPTION = 2;
    localparam NUM_RANDOM_RUNS = 5;

    integer          test_id;
    integer          seed;
    reg [8*16-1:0]   test_name;

    reg  [7:0] mat_a [0:7][0:7];                // A[row][k]
    reg  [7:0] mat_b [0:7][0:7];                // B[k][col]
    reg  [7:0] exp_c [0:7][0:7];                // Expected C[row][col]
    reg  [4:0] exp_flags;                       // Expected exception flags

    // Register values the CPU programs for one run
    reg  [9:0] addr_a, addr_b, addr_c;
    reg  [7:0] stride_a, stride_b, stride_c;

    reg  [`REG_DATAWIDTH-1:0] rdata;            // Last value read over APB
    reg  [4:0]  flags_read;                     // FLAGS register read after DONE
    reg         done;
    integer     polls;
    integer     runs, errors;

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
    // FP8 E3M4 reference model (shared with part_1 and part_3, see ../fp8_ref_model.vh)
    //////////////////////////////////////////////////////////////////////
`include "fp8_ref_model.vh"

    // Expected C and flags, accumulating in the same order as the PEs
    task compute_expected;
        integer   i, j, k;
        reg [7:0] product, sum;
        reg [4:0] mult_flags, add_flags;
        begin
            exp_flags = 5'b00000;
            for (i = 0; i < 8; i = i + 1) begin
                for (j = 0; j < 8; j = j + 1) begin
                    sum = 8'h00;
                    for (k = 0; k < 8; k = k + 1) begin
                        ref_mult(mat_a[i][k], mat_b[k][j], product, mult_flags);
                        ref_add(product, sum, sum, add_flags);
                        exp_flags = exp_flags | mult_flags | add_flags;
                    end
                    exp_c[i][j] = sum;
                end
            end
        end
    endtask

    //////////////////////////////////////////////////////////////////////
    // Test matrices
    //////////////////////////////////////////////////////////////////////
    // All elements of A and B are 1.0
    task set_ones_matrices;
        integer i, j;
        begin
            for (i = 0; i < 8; i = i + 1) begin
                for (j = 0; j < 8; j = j + 1) begin
                    mat_a[i][j] = 8'h30;    // 1.0
                    mat_b[i][j] = 8'h30;
                end
            end
        end
    endtask

    // Random finite FP8 value (same modes as the part 3 testbench).
    //   mode 0: any finite value
    //   mode 1: |x| < 1 (exponent 0-2), so sums stay finite and most results need rounding
    //   mode 2: sparse, one value in four is zero and the rest have |x| < 2
    task rand_fp8;
        input  integer mode;
        output [7:0]   x;
        reg    [31:0]  r;
        reg    [2:0]   e;
        begin
            r = $random(seed);
            case (mode)
                0:       e = r[14:12] % 7;
                1:       e = r[14:12] % 3;
                default: e = r[14:12] % 4;
            endcase
            x = {r[7], e, r[3:0]};
            if (mode == 2 && r[21:20] == 2'b00) x = 8'h00;
        end
    endtask

    task set_random_matrices;
        input integer mode;
        integer i, j;
        begin
            for (i = 0; i < 8; i = i + 1) begin
                for (j = 0; j < 8; j = j + 1) begin
                    rand_fp8(mode, mat_a[i][j]);
                    rand_fp8(mode, mat_b[i][j]);
                end
            end
        end
    endtask

    // Random register values: any base address and a stride of 1 to 16.
    // Addresses wrap around the 1024-word RAM, as the address counters do.
    task set_random_addresses;
        reg [31:0] r;
        begin
            r = $random(seed);
            addr_a   = r[9:0];
            addr_b   = r[19:10];
            addr_c   = r[29:20];
            r = $random(seed);
            stride_a = r[3:0] + 1;
            stride_b = r[11:8] + 1;
            stride_c = r[19:16] + 1;
        end
    endtask

    //////////////////////////////////////////////////////////////////////
    // Load the RAMs: column k of A and row k of B go to address
    // base + k * stride. A C sentinel catches a missing write.
    //////////////////////////////////////////////////////////////////////
    task load_rams;
        integer    k, lane;
        reg [9:0]  wa, wb, wc;
        reg [31:0] word_a0, word_a1, word_b0, word_b1;
        begin
            for (k = 0; k < 8; k = k + 1) begin
                for (lane = 0; lane < 4; lane = lane + 1) begin
                    word_a0[8*lane +: 8] = mat_a[lane][k];
                    word_a1[8*lane +: 8] = mat_a[lane + 4][k];
                    word_b0[8*lane +: 8] = mat_b[k][lane];
                    word_b1[8*lane +: 8] = mat_b[k][lane + 4];
                end
                wa = addr_a + k * stride_a;
                wb = addr_b + k * stride_b;
                wc = addr_c + k * stride_c;
                u_matmul.matrix_A0.ram[wa] = word_a0;
                u_matmul.matrix_A1.ram[wa] = word_a1;
                u_matmul.matrix_B0.ram[wb] = word_b0;
                u_matmul.matrix_B1.ram[wb] = word_b1;
                u_matmul.matrix_C0.ram[wc] = 32'hDEADBEEF;
                u_matmul.matrix_C1.ram[wc] = 32'hDEADBEEF;
            end
        end
    endtask

    //////////////////////////////////////////////////////////////////////
    // CPU side: configure over APB, start, poll DONE, read FLAGS
    //////////////////////////////////////////////////////////////////////
    // Read a register back and compare it with the value expected
    task read_check;
        input [`REG_ADDRWIDTH-1:0] addr;
        input [`REG_DATAWIDTH-1:0] expected;
        begin
            read(addr, rdata);
            if (rdata !== expected) begin
                if (errors < 10)
                    $display("  MISMATCH (run %0d): register %0d = %h, expected %h",
                             runs, addr, rdata, expected);
                errors = errors + 1;
            end
        end
    endtask

    task configure;
        begin
            $display("Write the addresses and strides");
            write(`REG_MATA_ADDR, addr_a);
            write(`REG_MATB_ADDR, addr_b);
            write(`REG_MATC_ADDR, addr_c);
            write(`REG_STRA_ADDR, stride_a);
            write(`REG_STRB_ADDR, stride_b);
            write(`REG_STRC_ADDR, stride_c);

            $display("Read them back");
            read_check(`REG_MATA_ADDR, addr_a);
            read_check(`REG_MATB_ADDR, addr_b);
            read_check(`REG_MATC_ADDR, addr_c);
            read_check(`REG_STRA_ADDR, stride_a);
            read_check(`REG_STRB_ADDR, stride_b);
            read_check(`REG_STRC_ADDR, stride_c);
        end
    endtask

    task run_matmul;
        begin
            $display("Start the matmul");
            write(`REG_STRT_ADDR, 16'h0001);

            $display("Wait until done");
            polls = 0;
            do begin
                read(`REG_DONE_ADDR, rdata);
                done  = rdata[15];
                polls = polls + 1;
                // The first poll comes long before the matmul can finish, so a
                // DONE left over from the previous run would show up here
                if (polls == 1 && done) begin
                    $display("  MISMATCH (run %0d): DONE was not cleared by START", runs);
                    errors = errors + 1;
                end
            end while (done == 0);
            $display("DONE after %0d polls", polls);

            $display("Read the flags");
            read(`REG_FLAG_ADDR, rdata);
            flags_read = rdata[4:0];
            if (rdata[15:5] !== 0) begin
                $display("  MISMATCH (run %0d): FLAGS unused bits = %h", runs, rdata[15:5]);
                errors = errors + 1;
            end

            // START is cleared by hardware when the operation is done
            read_check(`REG_STRT_ADDR, 16'h0000);
        end
    endtask

    task check_result;
        input      show_c;      // Print every column of C
        integer    i, j;
        reg [9:0]  wc;
        reg [31:0] word_c0, word_c1;
        reg [7:0]  observed;
        begin
            for (j = 0; j < 8; j = j + 1) begin
                wc      = addr_c + j * stride_c;
                word_c0 = u_matmul.matrix_C0.ram[wc];
                word_c1 = u_matmul.matrix_C1.ram[wc];
                if (show_c)
                    $display("C col %0d (address %0d): C0 = %h  C1 = %h", j, wc, word_c0, word_c1);
                for (i = 0; i < 8; i = i + 1) begin
                    observed = (i < 4) ? word_c0[8*i +: 8] : word_c1[8*(i - 4) +: 8];
                    if (observed !== exp_c[i][j]) begin
                        if (errors < 10)
                            $display("  MISMATCH (run %0d): C[%0d][%0d] = %h, expected %h",
                                     runs, i, j, observed, exp_c[i][j]);
                        errors = errors + 1;
                    end
                end
            end
            $display("FLAGS read over APB = %b, expected %b", flags_read, exp_flags);
            if (flags_read !== exp_flags) begin
                if (errors < 10)
                    $display("  MISMATCH (run %0d): FLAGS = %b, expected %b",
                             runs, flags_read, exp_flags);
                errors = errors + 1;
            end
        end
    endtask

    task do_run;
        input show_c;
        begin
            $display("--- run %0d: A @ %0d stride %0d, B @ %0d stride %0d, C @ %0d stride %0d",
                     runs, addr_a, stride_a, addr_b, stride_b, addr_c, stride_c);
            compute_expected;
            load_rams;
            configure;
            run_matmul;
            check_result(show_c);
            runs = runs + 1;
        end
    endtask

    task write_test_name;
        if      (test_id == T_ONES)   $write("ones");
        else if (test_id == T_RANDOM) $write("random");
        else                          $write("exception");
    endtask

    //////////////////////////////////////////////////////////////////////
    // Main sequence
    //////////////////////////////////////////////////////////////////////
    integer run;

    initial begin
        reset   = 1'b1;
        PSEL    = 0;
        PENABLE = 0;
        PWRITE  = 0;
        PADDR   = 0;
        PWDATA  = 0;
        runs    = 0;
        errors  = 0;

        if (!$value$plusargs("TEST=%s", test_name)) test_name = "ones";
        if (!$value$plusargs("SEED=%d", seed))      seed = 1;

        if      (test_name == "ones")      test_id = T_ONES;
        else if (test_name == "random")    test_id = T_RANDOM;
        else if (test_name == "exception") test_id = T_EXCEPTION;
        else begin
            $display("FAIL: unknown test, use +TEST=ones, random or exception");
            $finish;
        end

`ifdef FSDB_DUMP
        if      (test_id == T_ONES)   $fsdbDumpfile("ones_apb.fsdb");
        else if (test_id == T_RANDOM) $fsdbDumpfile("random_apb.fsdb");
        else                          $fsdbDumpfile("exception_apb.fsdb");
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

        // Registers must come out of reset with the documented values
        read_check(`REG_DONE_ADDR, 16'h0000);
        read_check(`REG_STRA_ADDR, 16'h0001);

        if (test_id == T_RANDOM) begin
            $display("seed = %0d, %0d runs", seed, NUM_RANDOM_RUNS);
            for (run = 0; run < NUM_RANDOM_RUNS; run = run + 1) begin
                set_random_matrices(run % 3);
                set_random_addresses;
                do_run(1'b0);
            end
        end else begin
            set_ones_matrices;
            if (test_id == T_ONES) begin
                addr_a = 10'd16;  stride_a = 8'd1;
                addr_b = 10'd32;  stride_b = 8'd2;
                addr_c = 10'd64;  stride_c = 8'd3;
            end else begin
                mat_a[0][0] = 8'h60;    // 8.0
                mat_b[0][0] = 8'h60;    // 8.0 x 8.0 = 64 overflows to +inf
                addr_a = 10'd16;  stride_a = 8'd1;
                addr_b = 10'd32;  stride_b = 8'd1;
                addr_c = 10'd64;  stride_c = 8'd1;
            end
            do_run(1'b1);
            if (test_id == T_EXCEPTION && flags_read == 5'b00000) begin
                $display("  MISMATCH: the exception test raised no flag");
                errors = errors + 1;
            end
        end

        $display("%0d run(s), %0d mismatches, FLAGS = %b", runs, errors, flags_read);
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
        #2_000_000;
        $display("FAIL: timeout, DONE was not set");
        $finish;
    end

endmodule
