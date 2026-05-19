# FlashAttention Verification Plan

This plan covers the SystemVerilog module testbenches and the full UVM
verification environment for contest problem 2.

## Compliance Matrix

| Area | Goal | Implementation | Evidence |
|---|---|---|---|
| Verification points | Define planned checks for registers, DMA, AXI, function, performance, exceptions, and coverage | This file | `tb/verification/verification_plan.md` |
| Full UVM environment | Meet the contest requirement for a SystemVerilog+UVM verification environment | UVM interfaces, agents, sequences, scoreboard, coverage, env, and tests under `tb/uvm/` | `tb/uvm/fa_uvm_if.sv`, `tb/uvm/fa_uvm_pkg.sv`, `tb/uvm/fa_uvm_tb.sv`, `scripts/run_uvm_verification.sh` |
| AXI VIP | Check AXI4-Lite and AXI4 Master key protocol behavior | Lightweight VIP-lite monitors because no commercial AXI VIP was found under the available `/eda` Synopsys/Cadence paths | `tb/verification/fa_axi_vip_lite.sv` |
| UVM AXI VIP-lite | Integrate local protocol checking into UVM without commercial AXI VIP dependency | UVM AXI4-Lite active agent monitor and AXI master passive DMA monitor/checker | `tb/uvm/fa_uvm_pkg.sv` |
| Register model | RAL-like mirror/model for register reset, RW, RO, W1C, byte strobe, soft_reset, start/done | Enhanced verification TB register model and access tasks | `tb/verification/fa_verification_tb.sv` |
| UVM register sequences | Exercise defaults, RW, RO, W1C, byte strobes, soft_reset, causal config, start/done, and counters | `fa_uvm_reg_sequence` and `fa_uvm_attention_job_sequence` | `tb/uvm/fa_uvm_pkg.sv` |
| DMA | Check Q/K/V read ranges, O write range, burst bytes, byte counters, and final writeback | DMA monitor/checks in enhanced verification TB | `tb/verification/fa_verification_tb.sv` |
| UVM DMA scoreboard | Check Q/K/V/O byte ranges and exact byte counts from UVM AXI master monitor transactions | `fa_axi_master_monitor` and `fa_uvm_scoreboard` | `tb/uvm/fa_uvm_pkg.sv` |
| AXI protocol | Check valid-ready payload stability, legal burst size/len/burst type, WLAST/RLAST alignment, OKAY responses, WSTRB, no X/Z | AXI VIP-lite monitors | `tb/verification/fa_axi_vip_lite.sv` |
| Function/performance | Random Q/K/V end-to-end, FP32 golden, causal row0 corner, cycles `<300k`, RD/WR bytes summary | Existing system TB plus enhanced verification TB | `tb/unit_tb/system_tb.sv`, `tb/verification/fa_verification_tb.sv` |
| UVM function/performance | Deterministic Q/K/V end-to-end, FP32 causal golden, output comparison, cycles `<300k`, RD/WR byte counters | UVM scoreboard and `fa_uvm_causal_e2e_test` | `tb/uvm/fa_uvm_pkg.sv` |
| UVM bonus: padding mask | Runtime valid length masks padded Q/K/V rows and checks padded O rows stay zero | `VALID_LEN` register, tile bounds, compute mask, `fa_uvm_padding_mask_test` | `rtl/*.sv`, `tb/uvm/fa_uvm_pkg.sv`, `scripts/run_uvm_bonus.sh` |
| UVM bonus: multi-head | Sequential heads with runtime head count and head stride | `HEAD_COUNT`, `HEAD_STRIDE`, tile-controller head loop, `fa_uvm_multi_head_test` | `rtl/*.sv`, `tb/uvm/fa_uvm_pkg.sv`, `scripts/run_uvm_bonus.sh` |
| UVM bonus: task queue | At least two attention jobs captured from AXI4-Lite and executed back-to-back | Active-job capture, two-entry pending queue, `QUEUE_STATUS`, `fa_uvm_task_queue_test` | `rtl/flash_attention_top.sv`, `tb/uvm/fa_uvm_pkg.sv`, `scripts/run_uvm_bonus.sh` |
| Coverage | VCS line/cond/fsm/tgl/branch coverage and functional coverage for register access, start/done, causal, DMA, AXI burst/handshake, performance and error buckets | Coverage-enabled verification script and covergroups | `scripts/run_verification_suite.sh`, `tb/verification/fa_verification_tb.sv` |
| UVM coverage | Functional covergroups for register map, start/done flow, DMA regions, AXI burst characteristics, causal/performance buckets, and error-free completion | `fa_uvm_coverage`; code coverage through UVM runner | `scripts/run_uvm_verification.sh`, `tb/uvm/fa_uvm_pkg.sv` |

## UVM Environment Components

The project now includes a full SystemVerilog+UVM environment under `tb/uvm/`.
It reuses the RTL and the existing `axi4_slave_mem` model, but stimulus,
checking, and coverage are UVM components/classes rather than a module-only
wrapper.

- Interfaces: `fa_axil_if`, `fa_axi4_master_if`, `fa_mem_access_if`.
- Sequence items: `fa_axil_reg_item`, `fa_attention_job_item`, `fa_axi_dma_item`.
- Sequences: `fa_uvm_reg_sequence`, `fa_uvm_attention_job_sequence`, `fa_uvm_causal_e2e_sequence`, `fa_uvm_bonus_job_sequence`, and `fa_uvm_task_queue_sequence`.
- Agents: active `fa_axil_agent`; passive `fa_axi_dma_agent`.
- Driver: `fa_axil_driver` for AXI4-Lite register reads/writes.
- Monitors/checkers: `fa_axil_monitor` and `fa_axi_master_monitor`, implementing local UVM VIP-lite protocol checks.
- Scoreboard: `fa_uvm_scoreboard`, including FP32 golden model reuse, DMA byte/range checking, counter checks, performance check, and output comparison.
- Coverage: `fa_uvm_coverage`, with register, flow, DMA, AXI burst, performance, and error-free completion covergroups.
- Environment/tests: `fa_uvm_env`, `fa_uvm_base_test`, `fa_uvm_causal_e2e_test`, `fa_uvm_smoke_test`, `fa_uvm_padding_mask_test`, `fa_uvm_multi_head_test`, and `fa_uvm_task_queue_test`.

The UVM AXI protocol checks are local VIP-lite style checks and do not require
commercial AXI VIP. They check valid-ready payload stability, X/Z-free valid
payloads, OKAY responses, 16-byte aligned INCR bursts, 4KB burst boundaries,
full write strobes, and WLAST/RLAST alignment.

Latest passing UVM evidence:

- Command: `scripts/run_uvm_verification.sh`
- Simulation log: `build/vcs_uvm_verification/sim.log`
- Coverage report: `build/vcs_uvm_verification/coverage_report`
- Result: `cycles=299745`, `RD_BYTES=2260992`, `WR_BYTES=32768`, `mean_abs_error=0.002143`, `max_abs_error=0.005659`, `row0_causal=0.003906`, UVM warnings/errors/fatals `0/0/0`.

Latest passing UVM bonus evidence:

- Command: `VCS_BONUS_BUILD_ROOT=remote_codex_jobs/bonus_uvm_completion_20260520_010220/artifacts/vcs_uvm_bonus_retry VCS_ENABLE_COVERAGE=0 UVM_BONUS_TESTS="fa_uvm_multi_head_test fa_uvm_task_queue_test" bash scripts/run_uvm_bonus.sh`
- Padding log: `remote_codex_jobs/bonus_uvm_completion_20260520_010220/artifacts/vcs_uvm_bonus/fa_uvm_padding_mask_test/sim.log`
- Multi-head log: `remote_codex_jobs/bonus_uvm_completion_20260520_010220/artifacts/vcs_uvm_bonus_retry/fa_uvm_multi_head_test/sim.log`
- Task-queue log: `remote_codex_jobs/bonus_uvm_completion_20260520_010220/artifacts/vcs_uvm_bonus_retry/fa_uvm_task_queue_test/sim.log`
- Results: padding `VALID_LEN=130`, `cycles=88129`, `RD_BYTES=643584`, `WR_BYTES=16896`; multi-head `HEAD_COUNT=2`, `cycles=599489`, `RD_BYTES=4521984`, `WR_BYTES=65536`; queue two jobs, `QUEUE_STATUS=0x00000200`, aggregate DMA read/write `344064/16384`; all with UVM warnings/errors/fatals `0/0/0`.

## Contest-2 Bonus Matrix

| Bonus item | Status | Evidence |
|---|---:|---|
| BF16/FP16 version | NOT_DONE | Not implemented; no FP arithmetic path or UVM checker was added. |
| Multi-head support | PASS | Runtime `HEAD_COUNT/HEAD_STRIDE`; `fa_uvm_multi_head_test` checks two heads end-to-end. |
| Longer/configurable sequence | PARTIAL | Runtime `VALID_LEN` supports shorter configured sequence/padding up to compiled `SEQ_LEN=256`; no S=512 build was completed. |
| Padding mask | PASS | `VALID_LEN` masks invalid rows/cols; UVM checks padded O rows stay zero. |
| Additional Q formats Q6.10/Q4.12 | NOT_DONE | Not implemented; Q8.8 datapath remains the verified format. |
| Dropout training mode | NOT_DONE | Not implemented; no dropout datapath or checker was added. |
| INT8/FP8 direction | NOT_DONE | Not implemented; no lower-precision RTL path or checker was added. |
| AXI4-Stream interface | NOT_DONE | Not implemented in this pass. |
| DMA/task queue | PASS | Active-job capture plus two-entry pending queue; `fa_uvm_task_queue_test` verifies two queued jobs and two output regions. |

## Verification Points

### Register Access

- Reset defaults: `CTRL=0`, `STATUS=0`, `CFG=0`, base registers `0`, `STRIDE_BYTES=128`, `NEG_LARGE=0xFFFF8000`, `SCALE=0x20`, `VALID_LEN=256`, `HEAD_COUNT=1`, `HEAD_STRIDE=32768`, counters `0`.
- RW registers: `CFG`, Q/K/V/O base low/high, `STRIDE_BYTES`, `NEG_LARGE`, `SCALE`, `VALID_LEN`, `HEAD_COUNT`, `HEAD_STRIDE`.
- RO registers: `CYCLES`, `RD_BYTES`, `WR_BYTES`, `QUEUE_STATUS` ignore writes.
- STATUS behavior: `BUSY`, sticky `DONE`, write-1-clear `DONE`.
- CTRL behavior: `START` pulse, `SOFT_RESET` pulse, `IRQ_EN` storage.
- Byte strobes: partial AXI4-Lite writes update only selected byte lanes.
- Queue status: pending count, completed count, and overflow/error status.

### DMA

- Q reads remain within `[Q_BASE, Q_BASE + S*d*2)`.
- K reads remain within `[K_BASE, K_BASE + S*d*2)`.
- V reads remain within `[V_BASE, V_BASE + S*d*2)`.
- O writes remain within `[O_BASE, O_BASE + S*d*2)`.
- Read/write burst byte totals match `RD_BYTES` and `WR_BYTES`.
- O memory is written back before the final result comparison.

### AXI Protocol

- AXI4-Lite AW/W/AR payload stability while `VALID && !READY`.
- AXI4-Lite R/B responses are OKAY.
- AXI4-Lite write strobes are known and non-zero for test writes.
- AXI4 Master AW/AR payload stability while `VALID && !READY`.
- AXI4 Master bursts are INCR, 16-byte beat size, aligned, and 1 to 256 beats.
- WLAST and RLAST align with the announced burst length.
- AXI responses are OKAY.
- No X/Z on valid payloads.

### Function and Performance

- Random Q/K/V test vectors are generated in Q8.8 and loaded into external memory.
- FP32 golden uses the same causal scaled dot-product attention formula.
- `mean_abs_error <= 0.03`.
- `max_abs_error <= 0.10`.
- Causal row0 is checked against `V[0]`.
- `CYCLES < 300000`.
- Expected bandwidth counters: `RD_BYTES=2260992`, `WR_BYTES=32768`.
- Bonus padding/multi-head/task-queue tests compute expected DMA bytes dynamically from `VALID_LEN`, `HEAD_COUNT`, and queued jobs.

### Coverage Targets

- Register address access: all implemented RW/RO/W1C registers.
- Register access kind: read and write.
- Byte strobe bins: full and partial strobes.
- Control flow: soft reset, start, busy observed, done observed, done W1C clear, causal enabled, padding, multi-head, and queue completion.
- DMA regions: Q, K, V reads and O writes.
- AXI channels: AW, W, B, AR, R handshakes.
- Burst lengths: Q/O tile bursts and K/V tile bursts.
- Performance bucket: pass bucket under 300k cycles and a multi-head bucket under 600k cycles.
- Error bucket: pass buckets for mean/max/causal thresholds.
