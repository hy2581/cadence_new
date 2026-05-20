# FlashAttention UVM Signoff Flow

This flow is the contest-facing verification path for the practice Synopsys
environment. It focuses on RTL correctness and UVM evidence for the baseline and
bonus feature set. Synthesis, physical timing, and area are treated as auxiliary
evidence, not as the primary pass/fail gate for this practice project.

## Scope

The signoff flow verifies:

- Baseline `S=256, d=64, batch=1, head=1` causal attention.
- AXI4-Lite register programming, defaults, RW/RO/W1C behavior, byte strobes,
  soft reset, start, busy, and done.
- AXI4 master DMA address ranges, burst shape, byte accounting, and output
  writeback.
- Random Q/K/V end-to-end output comparison against an FP32 golden model with
  the documented mean/max error thresholds.
- Causal row-0 corner behavior.
- Bonus behavior: padding mask, multi-head, task queue, external BF16/FP16 I/O,
  external Q6.10/Q4.12 I/O, deterministic dropout, external INT8 Q4.4 and FP8
  E4M3 I/O, AXI4-Stream bridge smoke, and compile-time `SEQ_LEN=512` bounded
  test coverage.

## UVM Architecture

The environment under `tb/uvm/` is a real UVM testbench:

- Interfaces: `fa_axil_if`, `fa_axi4_master_if`, `fa_mem_access_if`,
  `fa_axis_if`.
- Sequence items: `fa_axil_reg_item`, `fa_attention_job_item`,
  `fa_axi_dma_item`, `fa_axis_item`.
- Agents: active AXI4-Lite agent and passive AXI4 master DMA agent.
- Monitors: AXI4-Lite, AXI4 master, and AXI4-Stream monitors.
- Scoreboard: golden-model output comparison, DMA byte/range checking, register
  status/counter checking, and AXI4-Stream ordered payload checking.
- Coverage: register access, flow events, DMA regions, AXI bursts, performance
  buckets, format/dropout/AXIS flow points, and error-free completion.
- Tests: `fa_uvm_causal_e2e_test`, `fa_uvm_padding_mask_test`,
  `fa_uvm_multi_head_test`, `fa_uvm_task_queue_test`,
  `fa_uvm_bf16_fp16_test`, `fa_uvm_fixed_format_test`,
  `fa_uvm_int8_fp8_test`, `fa_uvm_dropout_test`, `fa_uvm_axis_smoke_test`, and
  `fa_uvm_seq512_test`.

The AXI checks are local VIP-lite checks implemented in UVM monitors. They are
not commercial AXI VIP, but they verify the protocol properties this design
depends on: stable valid-ready payloads, known payloads, OKAY responses, legal
INCR bursts, aligned beat sizes, full write strobes where required, and
WLAST/RLAST alignment.

## Release Flow

Run the full signoff entry point:

```bash
bash scripts/run_uvm_signoff.sh
```

Default behavior:

- Runs script syntax preflight.
- Runs baseline `fa_uvm_causal_e2e_test` with coverage enabled.
- Runs the full bonus regression with isolated build directories.
- Runs the `SEQ_LEN=512` compiled variant through `scripts/run_uvm_bonus_full.sh`.
- Writes `build/vcs_uvm_signoff/uvm_signoff_summary.md`.

For a final release where runtime is acceptable, enable coverage on the bonus
suite too:

```bash
UVM_SIGNOFF_BONUS_COVERAGE=1 bash scripts/run_uvm_signoff.sh
```

For an isolated bonus-only rerun:

```bash
VCS_BONUS_FULL_BUILD_ROOT=build/vcs_uvm_bonus_full \
VCS_ENABLE_COVERAGE=0 \
  bash scripts/run_uvm_bonus_full.sh
```

For a single UVM test debug run:

```bash
VCS_BUILD_DIR=build/vcs_uvm_debug/fa_uvm_dropout_test \
UVM_TESTNAME=fa_uvm_dropout_test \
VCS_ENABLE_COVERAGE=0 \
  bash scripts/run_uvm_verification.sh
```

## Pass Criteria

A UVM signoff run is acceptable only when all of the following hold:

- VCS compile exits successfully for every test build.
- Every simulation exits successfully.
- Every final log reports `UVM_ERROR : 0` and `UVM_FATAL : 0`.
- The baseline UVM test reports `cycles < 300000`.
- Baseline output comparison passes `mean_abs_error <= 0.03` and
  `max_abs_error <= 0.10`.
- Baseline DMA counters match the expected `RD_BYTES=2260992` and
  `WR_BYTES=32768`.
- Bonus tests pass their own scoreboard checks and do not rely only on smoke
  completion.
- Coverage reports are archived for the coverage-enabled run.

## Feature Scope Notes

These notes are intentional and should remain visible in review:

- BF16/FP16, FP8, INT8, Q6.10, and Q4.12 are external tensor I/O modes around
  the internal Q8.8 compute core. They are not native floating-point arithmetic
  datapaths.
- INT8 and FP8 use the lower byte of each existing 16-bit tensor lane; they do
  not reduce memory bandwidth.
- The `SEQ_LEN=512` test compiles a 512-row design and runs bounded
  `VALID_LEN=260`, proving addressing and comparison beyond row 255. It is not a
  full 512-row runtime.
- The AXI4-Stream test verifies a standalone ready/valid stream bridge with
  scoreboard-visible data movement. It is not a full attention-over-AXIS
  ingress/egress datapath.

## Current Evidence Snapshot

The latest remote evidence before this flow document was added is:

- Run directory:
  `remote_codex_jobs/bonus_full_uvm_20260520_013839`.
- Full final bonus logs:
  `remote_codex_jobs/bonus_full_uvm_20260520_013839/artifacts/vcs_uvm_bonus_full_final/*/sim.log`.
- Post-bonus system TB:
  `remote_codex_jobs/bonus_full_uvm_20260520_013839/artifacts/vcs_system_tb_after_synth_fix/sim.log`.
- Result: every final bonus-suite log reports UVM warnings/errors/fatals
  `0/0/0`; post-bonus system TB reports `>>> ALL TESTS PASSED <<<`.
