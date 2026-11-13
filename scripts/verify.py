#!/usr/bin/env python3
"""Check everything:

  1. assembler encodings
  2. the unit testbenches
  3. every program on all four systems, in three configurations, against
     the reference model (iss.py): every retired instruction, every register
     write, every store and every output must match
  4. the same for randomly generated programs

    python3 scripts/verify.py

Needs Python 3 and Icarus Verilog. Exits with an error if anything fails.
"""

import sys
import zlib
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import iss
import random_program
import sim
import test_asm

UNIT_TESTBENCHES = ["tb_datapath", "tb_hazard", "tb_rw_control", "tb_interconnect", "tb_cache"]
# (wait states, cache sets): fast memory, slow memory, tiny 64-byte caches that evict all the time
CONFIGS = [(0, 64), (3, 64), (1, 4)]
RANDOM_PROGRAMS = 30
PROGRAMS = ["isa_test", "qsort", "matmul", "crc32", "listwalk", "memcpy", "collatz",
            "sep_test", "smc_test", "smc_nofence"]


def xorshift_words(seed, count):
    words = []
    x = seed
    for _ in range(count):
        x ^= (x << 13) & 0xFFFFFFFF
        x ^= x >> 17
        x ^= (x << 5) & 0xFFFFFFFF
        words.append(x)
    return words


def collatz_steps(n):
    steps = 0
    while n != 1:
        n = n // 2 if n % 2 == 0 else 3 * n + 1
        steps += 1
    return steps


def independent_results():
    """What each benchmark must print, computed directly in Python (not by iss.py)."""
    array = [word >> 8 for word in xorshift_words(0x12345678, 256)]
    a = [[(i + 2 * j) & 15 for j in range(16)] for i in range(16)]
    b = [[(3 * i + j) & 15 for j in range(16)] for i in range(16)]
    c = [[sum(a[i][k] * b[k][j] for k in range(16)) for j in range(16)] for i in range(16)]
    buffer = b"".join(word.to_bytes(4, "little") for word in xorshift_words(0x2545F491, 256))
    return {
        "isa_test": [0x600D],
        "qsort": [sum(array) & 0xFFFFFFFF, 0, min(array), max(array)],
        "matmul": [sum(map(sum, c)), c[0][0], c[15][15]],
        "crc32": [zlib.crc32(buffer)],
        "listwalk": [4 * sum(k ^ 0x55 for k in range(512))],
        "memcpy": [sum(5 * i for i in range(1024))],
        "collatz": [sum(collatz_steps(n) for n in range(1, 201))],
        "smc_test": [1, 2],
        "smc_nofence": [1, 2],
    }


def expectation(name, system):
    if system == "harvard" and name in ("sep_test", "smc_test", "smc_nofence"):
        return "bus_error"          # the Harvard data side cannot reach code space
    if system == "split_cache" and name == "smc_nofence":
        return "stale"              # no FENCE.I: the I-cache runs the old instruction
    return "match"


def check(name, system, result, reference, harvard_reference):
    """Return a list of problems (empty when the run is correct)."""
    problems = list(result["errors"])
    stats = result["stats"]
    if stats:
        empty_slots = sum(stats[key] for key in stats if key.startswith("why_"))
        if stats["cycles"] != stats["instret"] + empty_slots:
            problems.append("cycle breakdown does not add up")
    expected = expectation(name, system)
    if expected == "bus_error":
        if not result["bus_error"]:
            problems.append("expected a bus error")
        if result["commits"] != harvard_reference.commits:
            problems.append("commit log differs from the reference before the bus error")
    elif expected == "stale":
        if result["outputs"] != [1, 1]:
            problems.append(f"expected the stale result [1, 1], got {result['outputs']}")
    else:
        if result["bus_error"]:
            problems.append("unexpected bus error")
        if result["commits"] != reference.commits:
            index = next((i for i, (a, b) in enumerate(zip(result["commits"], reference.commits)) if a != b),
                         min(len(result["commits"]), len(reference.commits)))
            problems.append(f"commit log differs from the reference at instruction {index}")
        if result["stores"] != reference.stores:
            problems.append("store log differs from the reference")
        if result["outputs"] != reference.outputs:
            problems.append(f"printed {result['outputs']}, reference printed {reference.outputs}")
    return problems


def main():
    failures = []

    test_asm.run()
    print(f"PASS test_asm: {len(test_asm.CASES)} cases")

    for testbench in UNIT_TESTBENCHES:
        simulator = sim.BUILD / testbench
        sim.BUILD.mkdir(exist_ok=True)
        sim.run(sim.IVERILOG + ["-s", testbench, "-o", str(simulator), f"tb/{testbench}.v"] + sim.RTL_FILES)
        first_line = sim.run(["vvp", "-n", str(simulator)]).splitlines()[0]
        print(first_line)
        if not first_line.startswith("PASS"):
            failures.append(testbench)

    # Programs: hand-written ones, then random ones
    images = {}
    for name in PROGRAMS:
        images[name] = sim.assemble(sim.ROOT / "programs" / f"{name}.s", sim.BUILD / name)
    random_dir = sim.BUILD / "random"
    random_dir.mkdir(parents=True, exist_ok=True)
    for seed in range(RANDOM_PROGRAMS):
        source = random_dir / f"random{seed}.s"
        source.write_text(random_program.generate(seed))
        images[f"random{seed}"] = sim.assemble(source, random_dir / f"random{seed}")

    # The reference model, and an independent check of the reference model
    references = {}
    harvard_references = {}
    independent = independent_results()
    for name, (code_hex, data_hex, _) in images.items():
        code = iss.read_hex(code_hex)
        data = iss.read_hex(data_hex)
        references[name] = iss.Machine(code, data)
        references[name].run()
        harvard_references[name] = iss.Machine(code, data, harvard=True)
        harvard_references[name].run()
        if name in independent and references[name].outputs != independent[name]:
            failures.append(f"reference model on {name}")
            print(f"FAIL reference model: {name} printed {references[name].outputs}, expected {independent[name]}")

    simulators = {}
    for system in sim.SYSTEMS:
        for wait, sets in CONFIGS:
            simulators[(system, wait, sets)] = sim.build_simulator(system, wait, sets)

    jobs = [(name, key) for name in images for key in simulators]

    def run_job(job):
        name, key = job
        code_hex, data_hex, _ = images[name]
        result = sim.simulate(simulators[key], code_hex, data_hex, log=True)
        return job, check(name, key[0], result, references[name], harvard_references[name])

    problems_by_program = {name: [] for name in images}
    failed_runs = {name: 0 for name in images}
    with ThreadPoolExecutor() as pool:
        for (name, key), problems in pool.map(run_job, jobs):
            failed_runs[name] += bool(problems)
            for problem in problems:
                problems_by_program[name].append(f"{key[0]} (wait {key[1]}, {key[2]} sets): {problem}")

    runs_per_program = len(simulators)
    random_failures = 0
    for name, problems in problems_by_program.items():
        if name.startswith("random"):
            random_failures += bool(problems)
            for problem in problems:
                print(f"FAIL {name}: {problem}")
            continue
        status = "PASS" if not problems else "FAIL"
        print(f"{status} {name:12s} {runs_per_program - failed_runs[name]}/{runs_per_program} runs")
        for problem in problems:
            print(f"     {problem}")
        if problems:
            failures.append(name)
    print(f"{'PASS' if random_failures == 0 else 'FAIL'} random programs: "
          f"{RANDOM_PROGRAMS - random_failures}/{RANDOM_PROGRAMS} programs x {runs_per_program} runs match the reference")
    if random_failures:
        failures.append("random programs")

    if failures:
        sys.exit(f"\nFAILED: {', '.join(failures)}")
    print(f"\nAll checks passed ({len(jobs)} simulations).")


if __name__ == "__main__":
    main()
