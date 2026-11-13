#!/bin/sh
# Synthesis of the four systems with Yosys for a Xilinx 7-series FPGA, with
# one wait state so main memory maps to block RAM and 1 KB caches.
# Writes results/synth/<system>.txt. Run verify.py first (it writes build/matmul.code.hex,
# which becomes the Harvard instruction ROM; the other memories are RAM).
set -e
cd "$(dirname "$0")/.."
mkdir -p results/synth

for top in vonneumann_top harvard_top modharvard_top unicache_top; do
    program=""
    if [ "$top" = "harvard_top" ]; then
        program="chparam -set PROGRAM \"build/matmul.code.hex\" $top"
    fi
    yosys -q -l "results/synth/$top.log" -p "
        read_verilog rtl/*.v
        chparam -set MEM_WAIT 1 $top
        $program
        synth_xilinx -top $top -flatten
        tee -q -o results/synth/$top.txt stat
    "
    echo "results/synth/$top.txt"
done
