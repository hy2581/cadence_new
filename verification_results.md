# FlashAttention Contest-2 Verification Status

This report tracks the RTL against the Contest-2 requirements for the
`S=256, d=64, batch=1, head=1` FlashAttention accelerator.

Last updated: 2026-05-20 01:24 CST.

## Tool Environment

- Simulator: Synopsys VCS X-2025.06
- Synthesis: Synopsys Design Compiler X-2025.06-SP4
- Target library: Sky130 HS `sky130_fd_sc_hs__tt_025C_1v80_noccsn.db`
- Remote workspace: `/home/hy258/cadence_new`

## Latest Completed VCS Result

Latest clean run:
`/home/hy258/cadence_new/build/vcs_verification_completion_system/sim.log`

```text
Cycles:         299745
RD_BYTES:       2260992
WR_BYTES:       32768
mean_abs_error: 0.001955
max_abs_error:  0.004405
row0_causal:    0.003906
>>> ALL TESTS PASSED <<<
```

Strict testbench checks passed:

- `cycles < 300000`
- `mean_abs_error <= 0.03`
- `max_abs_error <= 0.10`
- row-0 causal mask corner check
- `RD_BYTES == 2260992`
- `WR_BYTES == 32768`

## Verification Completion Suite

Enhanced verification run:
`/home/hy258/cadence_new/build/vcs_verification_completion/sim.log`

Coverage report:
`/home/hy258/cadence_new/build/vcs_verification_completion/coverage_report`

Coverage dashboard summary:

```text
SCORE  LINE   COND   TOGGLE FSM    BRANCH GROUP
 62.36  53.31  73.35  54.90  62.50  30.12 100.00
```

Additional verification added for the contest completion task:

- Verification plan / compliance matrix: `tb/verification/verification_plan.md`
- AXI VIP-lite protocol monitors: `tb/verification/fa_axi_vip_lite.sv`
- RAL-like register model and enhanced system TB: `tb/verification/fa_verification_tb.sv`
- VCS coverage script: `scripts/run_verification_suite.sh`

Enhanced suite result:

```text
Cycles:             299745
RD_BYTES:           2260992
WR_BYTES:           32768
DMA Q/K/V read:     32768 / 1114112 / 1114112
DMA O write:        32768
AXI AR/AW bursts:   1152 / 64
AXI R/W beats:      141312 / 2048
AXIL R/W accesses:  2957 / 25
mean_abs_error:     0.001955
max_abs_error:      0.004405
row0_causal:        0.003906
Functional coverage reg/flow/dma/axi/perf: 100.00 100.00 100.00 100.00 100.00
>>> VERIFICATION COMPLETION TESTS PASSED <<<
```

The lightweight VIP-lite monitors check valid-ready payload stability, legal
AXI4 burst shape, WLAST/RLAST alignment, OKAY responses, WSTRB legality, and
X/Z-free valid payloads. Commercial AXI VIP was not found in the available
`/eda` Cadence/Synopsys install paths, so this focused checker is documented as
the local AXI VIP substitute.

## UVM Verification Environment

Full UVM run:
`/home/hy258/cadence_new/build/vcs_uvm_verification/sim.log`

Coverage report:
`/home/hy258/cadence_new/build/vcs_uvm_verification/coverage_report`

UVM source and runner:

- `tb/uvm/fa_uvm_if.sv`
- `tb/uvm/fa_uvm_pkg.sv`
- `tb/uvm/fa_uvm_tb.sv`
- `scripts/run_uvm_verification.sh`

The UVM environment uses local UVM VIP-lite protocol checking, not commercial
AXI VIP. It contains AXI4-Lite and AXI4 master interfaces, an active AXI4-Lite
agent, a passive AXI DMA monitor/agent, register and attention-job sequence
items, reset/register/job sequences, scoreboard, functional coverage, env,
base test, `fa_uvm_causal_e2e_test`, and `fa_uvm_smoke_test`.

UVM result:

```text
UVM test:           fa_uvm_causal_e2e_test
Cycles:            299745
RD_BYTES:          2260992
WR_BYTES:          32768
DMA Q/K/V read:    32768 / 1114112 / 1114112
DMA O write:       32768
AXI AR/AW bursts:  1152 / 64
mean_abs_error:    0.002143
max_abs_error:     0.005659
row0_causal:       0.003906
UVM warnings/errors/fatals: 0 / 0 / 0
Functional coverage reg/flow/dma/axi/perf: 100.00 100.00 100.00 100.00 100.00
>>> UVM VERIFICATION TESTS PASSED <<<
```

UVM coverage dashboard summary:

```text
SCORE  LINE   COND   TOGGLE FSM    BRANCH GROUP
 58.90  44.52  87.88  33.12  62.50  25.37 100.00
```

Existing enhanced non-UVM preservation run after adding the UVM environment:
`/home/hy258/cadence_new/build/vcs_uvm_preserve_verification_suite/sim.log`

```text
Cycles:             299745
RD_BYTES:           2260992
WR_BYTES:           32768
mean_abs_error:     0.001955
max_abs_error:      0.004405
row0_causal:        0.003906
>>> VERIFICATION COMPLETION TESTS PASSED <<<
```

## Contest-2 Bonus UVM Results

This run adds three UVM-verified bonus features while preserving the default
single-head `S=256, d=64` causal behavior.

Bonus runner:
`scripts/run_uvm_bonus.sh`

Passing bonus evidence:

```text
fa_uvm_padding_mask_test:
  log: remote_codex_jobs/bonus_uvm_completion_20260520_010220/artifacts/vcs_uvm_bonus/fa_uvm_padding_mask_test/sim.log
  VALID_LEN=130, cycles=88129, RD_BYTES=643584, WR_BYTES=16896
  mean_abs_error=0.001097, max_abs_error=0.004618, UVM 0/0/0

fa_uvm_multi_head_test:
  log: remote_codex_jobs/bonus_uvm_completion_20260520_010220/artifacts/vcs_uvm_bonus_retry/fa_uvm_multi_head_test/sim.log
  HEAD_COUNT=2, cycles=599489, RD_BYTES=4521984, WR_BYTES=65536
  mean_abs_error=0.002140, max_abs_error=0.005659, UVM 0/0/0

fa_uvm_task_queue_test:
  log: remote_codex_jobs/bonus_uvm_completion_20260520_010220/artifacts/vcs_uvm_bonus_retry/fa_uvm_task_queue_test/sim.log
  two queued jobs, QUEUE_STATUS=0x00000200, aggregate DMA read/write=344064/16384
  mean_abs_error=0.000529, max_abs_error=0.004344, UVM 0/0/0
```

Final preservation evidence after the bonus RTL changes:

```text
Baseline UVM:
  log: remote_codex_jobs/bonus_uvm_completion_20260520_010220/artifacts/vcs_uvm_baseline_final/sim.log
  cycles=299745, RD_BYTES=2260992, WR_BYTES=32768
  mean_abs_error=0.002143, max_abs_error=0.005659, UVM 0/0/0

System TB:
  log: remote_codex_jobs/bonus_uvm_completion_20260520_010220/artifacts/vcs_system_tb/sim.log
  cycles=299745, RD_BYTES=2260992, WR_BYTES=32768
  mean_abs_error=0.001955, max_abs_error=0.004405
  >>> ALL TESTS PASSED <<<
```

Contest-2 bonus matrix:

| Bonus item | Status | Evidence |
|---|---:|---|
| BF16/FP16 version | NOT_DONE | Not implemented; no FP arithmetic path or UVM checker was added. |
| Multi-head support | PASS | Runtime `HEAD_COUNT/HEAD_STRIDE`; `fa_uvm_multi_head_test` checks two heads end-to-end. |
| Longer/configurable sequence | PARTIAL | Runtime `VALID_LEN` supports shorter configured sequence/padding up to compiled `SEQ_LEN=256`; no S=512 build was completed. |
| Padding mask | PASS | `VALID_LEN` masks invalid rows/cols; `fa_uvm_padding_mask_test` checks padded O rows stay zero. |
| Additional Q formats Q6.10/Q4.12 | NOT_DONE | Not implemented; Q8.8 remains the verified fixed-point format. |
| Dropout training mode | NOT_DONE | Not implemented; no dropout datapath or checker was added. |
| INT8/FP8 direction | NOT_DONE | Not implemented; no lower-precision RTL path or checker was added. |
| AXI4-Stream interface | NOT_DONE | Not implemented in this pass. |
| DMA/task queue | PASS | Active job plus two-entry pending queue; `fa_uvm_task_queue_test` verifies two queued jobs and two output regions. |

## Latest Completed DC Result

Latest clean run:
`/home/hy258/cadence_new/build/dc_quality_lint_timing_20260518_1523`

Key reports:

- QoR: `reports/dc_qor.rpt`
- Max timing: `reports/dc_timing_max.rpt`
- Min timing: `reports/dc_timing_min.rpt`
- Lint/design check: `reports/dc_check_design.rpt`
- Area: `reports/dc_area.rpt`

Summary from `dc_qor.rpt`:

```text
Critical Path Length:          9.76
Critical Path Slack:           0.00
Critical Path Clk Period:     10.00
Total Negative Slack:          0.00
No. of Violating Paths:        0.00
Worst Hold Violation:          0.00
Total Hold Violation:          0.00
No. of Hold Violations:        0.00
Max Trans Violations:             0
Max Cap Violations:               0
Cell Area:           7311294.140080
```

Worst max path:
`u_compute/u_oa/col_base_reg[3] -> u_compute/u_oa/o_acc_reg[1][58][37]`,
reported as `slack (MET) 0.00`.

The current DC result is setup/hold/transition/capacitance clean at 10ns, but
the setup margin is still exactly 0.00ns. The previous worst
`kv_buf_sel -> dot_product acc` path has been cut by registering dot-product
inputs, at the cost of 544 additional cycles. Further timing work should focus
on real RTL or microarchitectural margin, not on weakening constraints.

## SDF And Activity Power Closure Attempts

SDF export from the latest clean DC netlist/SDC succeeded on 2026-05-19:

- Command: `SDF_EXPORT_TAG=20260519_1647 bash scripts/run_sdf_export.sh`
- Log: `build/dc_sdf_export_20260519_1647/dc_sdf_export.log`
- DDC: `build/dc_sdf_export_20260519_1647/netlist/fa_top.ddc`
- SDF: `build/dc_sdf_export_20260519_1647/netlist/fa_top.sdf`
- SPEF/parasitics: `build/dc_sdf_export_20260519_1647/netlist/fa_top.spef`
- Export QoR: `build/dc_sdf_export_20260519_1647/reports/dc_sdf_export_qor.rpt`

SDF-annotated VCS GLS now completes with the opt-in Sky130 SDF condition-token
and async `RECREM` normalization:

- Command: `POST_SYNTH_BUILD_DIR=/home/hy258/cadence_new/build/vcs_sdf_async_warning_cleanup_gls POST_SYNTH_SDF=1 SDF_FILE=/home/hy258/cadence_new/build/dc_sdf_export_20260519_1647/netlist/fa_top.sdf POST_SYNTH_USE_SPECIFY=1 POST_SYNTH_NORMALIZE_SKY130_SDF=1 POST_SYNTH_NORMALIZE_SKY130_SDF_ASYNC=1 bash scripts/run_post_synth_sim.sh`
- Normalized SDF: `build/vcs_sdf_async_warning_cleanup_gls/fa_top.sky130_pathnames_async.sdf`
- Normalization report: `build/vcs_sdf_async_warning_cleanup_gls/sky130_sdf_normalization_report.txt`
- Compile log: `build/vcs_sdf_async_warning_cleanup_gls/compile.log`
- Simulation log: `build/vcs_sdf_async_warning_cleanup_gls/sim.log`
- Run summary: `remote_codex_jobs/sdf_async_warning_cleanup_20260519_210546/final.md`

The normalizer keeps the original exported SDF intact and rewrites only
standalone `A1N/A2N` tokens to `A1_N/A2_N` in `COND` lines inside affected
`o2bb2ai/a2bb2oi/o2bb2a` Sky130 HS `CELLTYPE` blocks. With the async opt-in, it
also merges adjacent `dfrtp/dfstp` async `RECOVERY`/`HOLD` records into the
single `RECREM` form present in the PDK specify blocks. It does not change
delay numbers, instances, hierarchy, or celltype names. The final report shows
`changed_cells=4020`, `changed_lines=48240`, `A1N_to_A1_N=36180`,
`A2N_to_A2_N=36180`, and `async_recrem_pairs=14708`.

SDF GLS system result:

```text
Cycles:         299745
RD_BYTES:       2260992
WR_BYTES:       32768
mean_abs_error: 0.001955
max_abs_error:  0.004405
row0_causal:    0.003906
>>> ALL TESTS PASSED <<<
```

The previous pathname and async timing-check blockers are closed in this run:
`SDFCOM_IANE=0`, `SDFCOM_TANE=0`, `SDFCOM_INF=0`, `SDFCOM_CFTC=0`,
`SDFCOM_NL=0`, and `WSUM=0`. Remaining annotation warnings are not clean timing
signoff: `SDFCOM_SWC=148`, `SDFCOM_IWSBA=55`, `SDFCOM_NDI=116`, `MDOTDS=5`,
`TFIPC=184`, `IPDW=3`, and `IDTS=2`; total compile `Warning-=513`,
`Error-=0`, `Fatal=0`. Simulation logs contain no
setup/hold/recovery/removal timing violation messages.

Activity-based DC power from RTL VCD/SAIF succeeded:

- Command: `POWER_ACTIVITY_TAG=20260519_1654 bash scripts/run_power_activity.sh`
- RTL simulation log: `build/vcs_power_activity_20260519_1654/sim.log`
- VCD: `build/vcs_power_activity_20260519_1654/fa_system_tb.vcd`
- SAIF: `build/dc_power_activity_20260519_1654/activity/fa_system_tb_dut.saif`
- VCD-to-SAIF log: `build/dc_power_activity_20260519_1654/vcd2saif.log`
- DC log: `build/dc_power_activity_20260519_1654/dc_power_activity.log`
- Power report: `build/dc_power_activity_20260519_1654/reports/dc_power_activity.rpt`
- Hierarchical report: `build/dc_power_activity_20260519_1654/reports/dc_power_activity_hier.rpt`

Activity power numbers:

```text
Cell Internal Power  =   2.2902  W
Net Switching Power  =  19.4931 mW
Total Dynamic Power  =   2.3097  W
Cell Leakage Power   =  78.6975 uW
Total table row      =   2.3107e+03 mW
```

DC accepted the SAIF, but the report contains annotation caveats:
3 switching-activity conflicts, ignored constant-net annotations, a clock
toggle conflict where DC used the annotated value, and unannotated sequential
cell outputs.

## Requirement Checklist

| Requirement | Status | Evidence |
|---|---:|---|
| Fixed problem size `S=256, d=64` | PASS | `rtl/include/fa_params.svh` |
| Q/K/V input signed Q8.8 16-bit | PASS | `DATA_WIDTH=16`, testbench fixed-point load |
| O output signed Q8.8 16-bit | PASS | `output_accumulator.sv` final Q16.16 to Q8.8 conversion with saturation |
| Dot-product accumulator at least 32-bit | PASS | `ACC_WIDTH=40` |
| No full `S x S` attention matrix storage | PASS | tile-local score/probability buffering only |
| Online softmax | PASS | running `m_old/l_old`, `exp(m_old-m_new)` rescale |
| K/V tiling | PASS | `TILE_BR=4`, `TILE_BC=16`; causal mode prunes unused future K/V tiles |
| Causal mask | PASS | row-0 causal corner passes in system TB |
| AXI4-Lite control/status registers | PASS | CTRL/STATUS/CFG/base/stride/NEG_LARGE/SCALE/CYCLES/RD_BYTES/WR_BYTES |
| Runtime padding valid length | PASS | `REG_VALID_LEN`; `fa_uvm_padding_mask_test` |
| Sequential multi-head bonus | PASS | `REG_HEAD_COUNT`, `REG_HEAD_STRIDE`; `fa_uvm_multi_head_test` |
| Two-job task queue bonus | PASS | Active-job capture, two-entry pending queue, `REG_QUEUE_STATUS`; `fa_uvm_task_queue_test` |
| Configurable sequence length | PARTIAL | Runtime `VALID_LEN` for `1..256`; no S=512 build variant completed |
| BF16/FP16 bonus | NOT_DONE | No BF16/FP16 RTL datapath or UVM checker |
| Q6.10/Q4.12 bonus | NOT_DONE | No alternate fixed-point format variant completed |
| Dropout training bonus | NOT_DONE | No dropout datapath or deterministic checker |
| INT8/FP8 bonus | NOT_DONE | No INT8/FP8 RTL datapath or UVM checker |
| AXI4-Stream data interface bonus | NOT_DONE | No AXI4-Stream wrapper/interface completed |
| AXI VIP / protocol checks | PASS | `tb/verification/fa_axi_vip_lite.sv`, enhanced suite PASS |
| Full UVM verification environment | PASS | `tb/uvm/`, `scripts/run_uvm_verification.sh`, `build/vcs_uvm_verification/sim.log` |
| Register model validation | PASS | RAL-like mirror in `tb/verification/fa_verification_tb.sv` covers defaults, RW/RO/W1C, byte strobe, soft_reset/start/done |
| AXI4 master DMA | PASS | DMA read/write through `dma_engine.sv` and `axi4_master_if.sv`; enhanced suite checks Q/K/V/O ranges and byte counts |
| Random Q/K/V end-to-end test | PASS | `tb/unit_tb/system_tb.sv` |
| Start/done flow | PASS | AXI4-Lite START plus DONE polling |
| Bandwidth statistics | PASS | `REG_RD_BYTES` and `REG_WR_BYTES` checked by system TB |
| Coverage | PASS | `build/vcs_verification_completion/coverage_report`; code metrics enabled and group coverage is 100% |
| Causal runtime below 300k cycles | PASS | latest VCS: 299,745 cycles |
| 10ns Sky130 HS DC setup/hold/DRC | PASS | `build/dc_quality_lint_timing_20260518_1523/reports/dc_qor.rpt` |
| Area evidence | RECORDED | Sky130 HS raw cell area `7311294.140080`; NAND2-equivalent normalization not reported by this DC run |
| SDF export | PASS | `build/dc_sdf_export_20260519_1647/netlist/fa_top.sdf`, plus DDC/SPEF in the same directory |
| SDF timing GLS | PASS with residual annotation warnings | `build/vcs_sdf_async_warning_cleanup_gls/sim.log`; normalized SDF removes pathname and async reset/set blockers (`IANE/TANE/INF/CFTC/NL/WSUM=0`), with residual `SWC/IWSBA/NDI` and non-SDF warning classes |
| Activity-based DC power | PASS | `build/dc_power_activity_20260519_1654/reports/dc_power_activity.rpt` |

## Known Follow-Up Items

- `dc_check_design.rpt` still contains LINT warnings, but the obvious RTL
  source issues were reduced. Remaining warnings are mainly buffer read-enable
  inputs, AXI response/id inputs that are intentionally ignored, constant AXI
  outputs, and synthesis optimization residue.
- Worst setup slack is exactly 0.00ns. Timing should be improved only through
  functionally justified RTL or microarchitectural changes.
- No-SDF gate-level/post-synthesis simulation passes with the generated Sky130
  functional wrapper overlay. The opt-in timing overlay plus normalized SDF
  now completes SDF GLS with matching functional metrics and no
  `IANE/TANE/INF/CFTC/NL/WSUM` warnings. This is still not a clean timing
  signoff because residual annotation warnings remain: `SDFCOM_SWC=148`,
  `SDFCOM_IWSBA=55`, and `SDFCOM_NDI=116`.
- Activity-based power is recorded from RTL VCD/SAIF and DC `read_saif`, with
  annotation caveats listed above. A gate-level SAIF with full post-synthesis
  name matching would be stronger evidence.

## Bandwidth Accounting

With causal K/V tile pruning:

- Q reads: `64 q_tiles * 512 B = 32768 B`
- K/V reads: `544 kv_tile_visits * 4096 B = 2228224 B`
- Total reads: `2260992 B`
- O writes: `64 q_tiles * 512 B = 32768 B`

The testbench reads `REG_RD_BYTES=0x44` and `REG_WR_BYTES=0x48` and fails if
these values differ from the expected causal-pruned transfer counts.

## Reproduction Commands

```bash
cd /home/hy258/cadence_new

VCS_BUILD_DIR=/home/hy258/cadence_new/build/vcs_quality_<tag> \
  bash scripts/run_system_tb.sh

VCS_BUILD_DIR=/home/hy258/cadence_new/build/vcs_verification_completion \
VCS_ENABLE_COVERAGE=1 \
  bash scripts/run_verification_suite.sh

VCS_BONUS_BUILD_ROOT=/home/hy258/cadence_new/build/vcs_uvm_bonus \
VCS_ENABLE_COVERAGE=0 \
  bash scripts/run_uvm_bonus.sh

DC_MAX_CORES=4 \
DC_OUT_DIR=/home/hy258/cadence_new/build/dc_quality_<tag> \
  bash scripts/run_dc.sh
```
