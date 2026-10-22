LAB 3 - PART II: FP8 Systolic Matrix Multiplier

DESIGN FILES
------------
design/matmul_pkg.sv
design/FP8_AddSub.sv
design/FP8_Mult.sv
design/matmul.sv
design/matmul_with_ram.sv

TESTBENCHES
-----------
tests/tb_normal_fp8_PASS.sv
    Mixed FP8 matrix multiplication test with no expected exception.

tests/tb_exception_fp8_PASS.sv
    FP8 matrix multiplication test that intentionally causes an
    overflow exception.

SIMULATION
----------

1. Load the Synopsys environment.

2. Normal FP8 test:

vcs -full64 -sverilog -debug_access+all \
../design/matmul_pkg.sv \
../design/FP8_AddSub.sv \
../design/FP8_Mult.sv \
../design/matmul.sv \
../design/matmul_with_ram.sv \
tb_normal_fp8_PASS.sv -o simv

./simv

Expected result:
NORMAL FP8 MATRIX TEST PASSED


3. Exception FP8 test:

vcs -full64 -sverilog -debug_access+all \
../design/matmul_pkg.sv \
../design/FP8_AddSub.sv \
../design/FP8_Mult.sv \
../design/matmul.sv \
../design/matmul_with_ram.sv \
tb_exception_fp8_PASS.sv -o simv

./simv

Expected result:
EXCEPTION FP8 MATRIX TEST PASSED

NOTES
-----
The design replaces the original integer multiply and add operations
inside seq_mac with the FP8 multiplier and FP8 adder developed in Part I.

Exception flags from the FP8 multiplier and adder are combined in each
MAC, and exception flags from all processing elements are combined into
the exception_flags output.
