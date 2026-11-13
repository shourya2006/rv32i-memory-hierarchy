"""Shared helpers for verify.py and experiments.py: assemble programs, build
the Icarus Verilog simulators, run them, and parse what they print."""

import os
import subprocess
import sys
from pathlib import Path

import asm

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
RTL_FILES = sorted(str(path) for path in (ROOT / "rtl").glob("*.v"))
IVERILOG = ["iverilog", "-g2005", "-Wall", "-Wno-timescale"]

# name: (top module, testbench defines)
SYSTEMS = {
    "vonneumann": ("vonneumann_top", []),
    "harvard": ("harvard_top", ["-DSYS_HARVARD"]),
    "split_cache": ("modharvard_top", ["-DSYS_SPLIT_CACHE"]),
    "unified_cache": ("unicache_top", ["-DSYS_UNIFIED_CACHE"]),
}

STAT_KEYS = ["cycles", "instret", "why_reset", "why_fetch", "why_load_use", "why_branch", "why_data",
             "why_fence", "loads", "stores", "mem_reads", "mem_writes", "i_blocked",
             "ic_access", "ic_miss", "dc_access", "dc_miss", "dc_writeback"]


def run(command, cwd=ROOT):
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stdout + result.stderr)
        sys.exit(f"command failed: {' '.join(str(part) for part in command)}")
    return result.stdout


def assemble(source_path, out_prefix):
    """Assemble one .s file; return (code hex path, data hex path, program)."""
    program, data = asm.assemble(Path(source_path).read_text())
    out_prefix = Path(out_prefix)
    out_prefix.parent.mkdir(parents=True, exist_ok=True)
    code_hex = out_prefix.with_name(out_prefix.name + ".code.hex")
    data_hex = out_prefix.with_name(out_prefix.name + ".data.hex")
    asm.write_hex(code_hex, [word for word, _ in program])
    asm.write_hex(data_hex, data)
    return code_hex, data_hex, program


def build_simulator(system, mem_wait, cache_sets):
    """Compile the system testbench for one configuration (reused if already built)."""
    top, defines = SYSTEMS[system]
    path = BUILD / "sims" / f"{system}_w{mem_wait}_s{cache_sets}"
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        run(IVERILOG + [f"-DTOP={top}"] + defines
            + [f"-Ptb_system.MEM_WAIT={mem_wait}", f"-Ptb_system.CACHE_SETS={cache_sets}",
               "-s", "tb_system", "-o", str(path), "tb/tb_system.v"] + RTL_FILES)
    return path


def hex_or_none(text):
    """Parse a hex field; X or Z bits (an undriven value) give None, which never matches."""
    try:
        return int(text, 16)
    except ValueError:
        return None


def simulate(simulator, code_hex, data_hex, log=False, trace=False, vcd=None):
    """Run one program. Return a dict with outputs, stats, bus_error, errors,
    commits, stores and trace lines."""
    # Paths relative to the project keep the plusargs short (the testbench holds 1024 characters).
    command = ["vvp", "-n", str(simulator),
               f"+CODE={os.path.relpath(code_hex, ROOT)}", f"+DATA={os.path.relpath(data_hex, ROOT)}"]
    if log:
        command.append("+LOG")
    if trace:
        command.append("+TRACE")
    if vcd:
        command.append(f"+VCD={os.path.relpath(vcd, ROOT)}")
    result = {"outputs": [], "stats": {}, "bus_error": False, "errors": [],
              "commits": [], "stores": [], "trace": []}
    for line in run(command).splitlines():
        if line.startswith("OUT "):
            result["outputs"].append(hex_or_none(line.split()[1]))
        elif line.startswith("C "):
            _, pc, rd, value = line.split()
            result["commits"].append((hex_or_none(pc), int(rd), hex_or_none(value)))
        elif line.startswith("S "):
            _, address, strobe, data = line.split()
            result["stores"].append((hex_or_none(address), hex_or_none(strobe), hex_or_none(data)))
        elif line.startswith("T "):
            result["trace"].append(line)
        elif line.startswith("RESULT "):
            for field in line.split()[1:]:
                key, value = field.split("=")
                result["stats"][key] = int(value)
        elif line.startswith("BUS_ERROR"):
            result["bus_error"] = True
        elif line.startswith("ERROR"):
            result["errors"].append(line)
    return result
