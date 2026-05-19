# Submission Checklist And Evidence Index

Last updated: 2026-05-20.

## Source Scope

- RTL: `rtl/*.sv`, `rtl/axis_stream_bridge.sv`, and `rtl/include/fa_params.svh`.
- Constraints: `constraints/flash_attention.sdc`.
- Verification TBs: `tb/unit_tb/system_tb.sv`, `tb/unit_tb/axi4_slave_mem.sv`, `tb/verification/fa_verification_tb.sv`, `tb/verification/fa_axi_vip_lite.sv`, `tb/uvm/fa_uvm_if.sv`, `tb/uvm/fa_uvm_pkg.sv`, `tb/uvm/fa_uvm_tb.sv`.
- Verification plan: `tb/verification/verification_plan.md`.
- Run scripts: `scripts/run_system_tb.sh`, `scripts/run_verification_suite.sh`, `scripts/run_uvm_verification.sh`, `scripts/run_uvm_bonus.sh`, `scripts/run_uvm_bonus_full.sh`, `scripts/run_dc.sh`, `scripts/run_dc.tcl`, `scripts/run_post_synth_sim.sh`, `scripts/normalize_sky130_sdf.py`, `scripts/run_sdf_export.sh`, `scripts/run_sdf_export.tcl`, `scripts/run_power_activity.sh`, `scripts/run_power_activity.tcl`, `scripts/sky130_env.sh`, `scripts/synopsys2025_env.sh`.

## Verification Evidence

- Latest full system PASS: `build/vcs_verification_completion_system/sim.log`.
- Latest enhanced verification PASS: `build/vcs_verification_completion/sim.log`.
- Latest full UVM PASS: `build/vcs_uvm_verification/sim.log`.
- Latest post-bonus baseline UVM PASS: `remote_codex_jobs/bonus_full_uvm_20260520_013839/artifacts/vcs_uvm_bonus_full_final/fa_uvm_causal_e2e_test/sim.log`.
- Latest bonus BF16/FP16 UVM PASS: `remote_codex_jobs/bonus_full_uvm_20260520_013839/artifacts/vcs_uvm_bonus_full_final/fa_uvm_bf16_fp16_test/sim.log`.
- Latest bonus Q6.10/Q4.12 UVM PASS: `remote_codex_jobs/bonus_full_uvm_20260520_013839/artifacts/vcs_uvm_bonus_full_final/fa_uvm_fixed_format_test/sim.log`.
- Latest bonus INT8/FP8 UVM PASS: `remote_codex_jobs/bonus_full_uvm_20260520_013839/artifacts/vcs_uvm_bonus_full_final/fa_uvm_int8_fp8_test/sim.log`.
- Latest bonus dropout UVM PASS: `remote_codex_jobs/bonus_full_uvm_20260520_013839/artifacts/vcs_uvm_bonus_full_final/fa_uvm_dropout_test/sim.log`.
- Latest bonus AXI4-Stream UVM PASS: `remote_codex_jobs/bonus_full_uvm_20260520_013839/artifacts/vcs_uvm_bonus_full_final/fa_uvm_axis_smoke_test/sim.log`.
- Latest bonus padding UVM PASS: `remote_codex_jobs/bonus_full_uvm_20260520_013839/artifacts/vcs_uvm_bonus_full_final/fa_uvm_padding_mask_test/sim.log`.
- Latest bonus multi-head UVM PASS: `remote_codex_jobs/bonus_full_uvm_20260520_013839/artifacts/vcs_uvm_bonus_full_final/fa_uvm_multi_head_test/sim.log`.
- Latest bonus task-queue UVM PASS: `remote_codex_jobs/bonus_full_uvm_20260520_013839/artifacts/vcs_uvm_bonus_full_final/fa_uvm_task_queue_test/sim.log`.
- Latest bonus S=512 UVM PASS: `remote_codex_jobs/bonus_full_uvm_20260520_013839/artifacts/vcs_uvm_bonus_full_final/fa_uvm_seq512_test/sim.log`.
- Latest post-bonus system TB PASS: `remote_codex_jobs/bonus_full_uvm_20260520_013839/artifacts/vcs_system_tb_after_synth_fix/sim.log`.
- Latest post-bonus DC analyze/elaborate/check_design: `remote_codex_jobs/bonus_full_uvm_20260520_013839/artifacts/dc_check_only_after_fix/reports/dc_check_design.rpt`.
- UVM coverage dashboard: `build/vcs_uvm_verification/coverage_report/dashboard.txt`.
- Existing enhanced non-UVM preservation PASS after UVM addition: `build/vcs_uvm_preserve_verification_suite/sim.log`.
- Post-completion polish verification PASS: `build/vcs_post_completion_polish/sim.log`.
- Post-completion polish coverage dashboard: `build/vcs_post_completion_polish/coverage_report/dashboard.txt`.
- Baseline completion coverage: `build/vcs_verification_completion/coverage_report/dashboard.txt`.

Coverage summary:

| Run | SCORE | LINE | COND | TOGGLE | FSM | BRANCH | GROUP |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `vcs_verification_completion` | 62.36 | 53.31 | 73.35 | 54.90 | 62.50 | 30.12 | 100.00 |
| `vcs_post_completion_polish` | 63.34 | 55.93 | 70.25 | 49.00 | 62.50 | 42.36 | 100.00 |
| `vcs_uvm_verification` | 58.90 | 44.52 | 87.88 | 33.12 | 62.50 | 25.37 | 100.00 |

The polish run keeps functional group coverage at 100% and raises branch coverage through TB-only EXP and VIP stall checks. No RTL or constraint change was made for this polish coverage pass.

The UVM run is the contest-facing full UVM environment. It uses local UVM
VIP-lite protocol checking rather than commercial AXI VIP and includes:
AXI4-Lite and AXI4 master interfaces, active AXI4-Lite agent, passive AXI DMA
monitor/agent, register transaction and attention-job sequence items,
reset/register/job sequences, scoreboard, coverage component, env, base test,
`fa_uvm_causal_e2e_test`, and `fa_uvm_smoke_test`. The passing UVM metrics are
`cycles=299745`, `RD_BYTES=2260992`, `WR_BYTES=32768`,
`DMA_Q/K/V=32768/1114112/1114112`, `DMA_O=32768`,
`mean_abs_error=0.002143`, `max_abs_error=0.005659`,
`row0_causal=0.003906`, with UVM warnings/errors/fatals `0/0/0`.

Contest-2 bonus UVM status:

| Bonus item | Status | Evidence |
| --- | ---: | --- |
| BF16/FP16 version | PASS | External BF16/FP16 I/O modes through `REG_FORMAT`, verified by `fa_uvm_bf16_fp16_test`; internal compute remains Q8.8. |
| Multi-head support | PASS | Runtime `HEAD_COUNT/HEAD_STRIDE`; `fa_uvm_multi_head_test` checks two heads end-to-end. |
| Longer/configurable sequence | PASS | Compile-time `SEQ_LEN=512` via `FA_SEQ_LEN_OVERRIDE`, bounded `VALID_LEN=260` UVM comparison in `fa_uvm_seq512_test`. |
| Padding mask | PASS | `VALID_LEN` masks invalid rows/cols; `fa_uvm_padding_mask_test` checks padded O rows stay zero. |
| Additional Q formats Q6.10/Q4.12 | PASS | External Q6.10/Q4.12 I/O modes verified by `fa_uvm_fixed_format_test`. |
| Dropout training mode | PASS | Deterministic inverted dropout on attention probabilities, controlled by enable/rate/seed registers and checked by `fa_uvm_dropout_test`. |
| INT8/FP8 direction | PASS | External lower-precision modes: lane-aligned INT8 Q4.4 and FP8 E4M3, checked by `fa_uvm_int8_fp8_test`; no packed bandwidth reduction. |
| AXI4-Stream interface | PASS | Standalone `axis_stream_bridge` ready/valid bridge verified by `fa_uvm_axis_smoke_test`; not an attention-over-AXIS datapath. |
| DMA/task queue | PASS | Active job plus two-entry pending queue; `fa_uvm_task_queue_test` verifies two queued jobs and output regions. |

Bonus run metrics:

```text
fa_uvm_bf16_fp16_test:    FP16/BF16 external I/O modes, final mean_abs_error=0.000528, max_abs_error=0.004305, UVM 0/0/0
fa_uvm_fixed_format_test: Q6.10/Q4.12 external I/O modes, final mean_abs_error=0.000528, max_abs_error=0.004305, UVM 0/0/0
fa_uvm_int8_fp8_test:     INT8 Q4.4/FP8 E4M3 external I/O modes, final mean_abs_error=0.000552, max_abs_error=0.008006, UVM 0/0/0
fa_uvm_dropout_test:      VALID_LEN=64, dropout_rate=64, seed=0xC0DE5EED, mean_abs_error=0.000523, max_abs_error=0.004649, UVM 0/0/0
fa_uvm_axis_smoke_test:   8 scoreboard-checked AXI4-Stream beats with backpressure, UVM 0/0/0
fa_uvm_padding_mask_test: VALID_LEN=130, cycles=88129, RD_BYTES=643584, WR_BYTES=16896, UVM 0/0/0
fa_uvm_multi_head_test:   HEAD_COUNT=2, cycles=599489, RD_BYTES=4521984, WR_BYTES=65536, UVM 0/0/0
fa_uvm_task_queue_test:   QUEUE_STATUS=0x00000200, aggregate DMA read/write=344064/16384, UVM 0/0/0
fa_uvm_seq512_test:       FA_SEQ_LEN_OVERRIDE=512, bounded VALID_LEN=260, cycles=308857, RD_BYTES=2331136, WR_BYTES=33280, UVM 0/0/0
```

## Synthesis Evidence

- Latest clean DC run: `build/dc_quality_lint_timing_20260518_1523`.
- Netlist: `build/dc_quality_lint_timing_20260518_1523/netlist/fa_top_netlist.v`.
- Exported SDC: `build/dc_quality_lint_timing_20260518_1523/netlist/fa_top.sdc`.
- QoR: `build/dc_quality_lint_timing_20260518_1523/reports/dc_qor.rpt`.
- Area: `build/dc_quality_lint_timing_20260518_1523/reports/dc_area.rpt`.
- Timing max/min: `build/dc_quality_lint_timing_20260518_1523/reports/dc_timing_max.rpt`, `build/dc_quality_lint_timing_20260518_1523/reports/dc_timing_min.rpt`.
- Power: `build/dc_quality_lint_timing_20260518_1523/reports/dc_power.rpt`.
- Check design/reference/resources: `build/dc_quality_lint_timing_20260518_1523/reports/dc_check_design.rpt`, `dc_reference.rpt`, `dc_resources.rpt`.

DC summary from the latest reviewed run: 10 ns setup/hold/transition/cap clean, `WNS=0.00`, `TNS=0.00`, and cell area `7311294.140080`.

## Post-Synthesis Simulation

- Script: `scripts/run_post_synth_sim.sh`.
- Build/log directory for the polish attempt: `build/vcs_post_completion_polish_gls`.
- Result: PASS, `>>> ALL TESTS PASSED <<<` in `build/vcs_post_completion_polish_gls/sim.log`.
- Compile log: `build/vcs_post_completion_polish_gls/compile.log`.
- Simulation mode: no-SDF gate-level VCS with the latest DC netlist and Sky130 HS functional wrappers.
- Cell model source searched/used: `/home/hy258/cadence_codex_run_20260430_2114/pdk/src/skywater-pdk-libs-sky130_fd_sc_hs/cells`.
- Local generated overlay: `build/vcs_post_completion_polish_gls/sky130_model_overlay`.
- Result metrics: `cycles=299745`, `RD_BYTES=2260992`, `WR_BYTES=32768`, `mean_abs_error=0.001955`, `max_abs_error=0.004405`, `row0_causal=0.003906`.

This flow is intended as extra evidence. It does not replace the clean DC timing reports, because the available model set is a functional/no-SDF wrapper flow rather than a timing-annotated signoff simulation deck.

## SDF Export And Timing GLS

- SDF export script: `scripts/run_sdf_export.sh`, `scripts/run_sdf_export.tcl`.
- SDF export command: `SDF_EXPORT_TAG=20260519_1647 bash scripts/run_sdf_export.sh`.
- Result: PASS for export from the latest clean DC netlist/SDC.
- Export log: `build/dc_sdf_export_20260519_1647/dc_sdf_export.log`.
- DDC: `build/dc_sdf_export_20260519_1647/netlist/fa_top.ddc`.
- SDF: `build/dc_sdf_export_20260519_1647/netlist/fa_top.sdf`.
- SPEF/parasitics: `build/dc_sdf_export_20260519_1647/netlist/fa_top.spef`.
- Export QoR: `build/dc_sdf_export_20260519_1647/reports/dc_sdf_export_qor.rpt`.
- Original SDF GLS command attempted: `POST_SYNTH_BUILD_DIR=/home/hy258/cadence_new/build/vcs_sdf_power_closure_gls POST_SYNTH_SDF=1 SDF_FILE=/home/hy258/cadence_new/build/dc_sdf_export_20260519_1647/netlist/fa_top.sdf bash scripts/run_post_synth_sim.sh`.
- Latest normalized timing-overlay SDF GLS command: `POST_SYNTH_BUILD_DIR=/home/hy258/cadence_new/build/vcs_sdf_async_warning_cleanup_gls POST_SYNTH_SDF=1 SDF_FILE=/home/hy258/cadence_new/build/dc_sdf_export_20260519_1647/netlist/fa_top.sdf POST_SYNTH_USE_SPECIFY=1 POST_SYNTH_NORMALIZE_SKY130_SDF=1 POST_SYNTH_NORMALIZE_SKY130_SDF_ASYNC=1 bash scripts/run_post_synth_sim.sh`.
- SDF GLS result: PASS with residual annotation warnings, not clean timing signoff.
- Original SDF GLS compile log: `build/vcs_sdf_power_closure_gls/compile.log`.
- Prior timing-overlay partial compile log: `build/vcs_sdf_specify_timing_gls_fix4_compliant/compile.log`.
- Prior pathname-normalized compile log: `build/vcs_sdf_pathname_mapping_gls/compile.log`.
- Prior pathname-normalized simulation log: `build/vcs_sdf_pathname_mapping_gls/sim.log`.
- Async-cleaned timing-overlay compile log: `build/vcs_sdf_async_warning_cleanup_gls/compile.log`.
- Async-cleaned timing-overlay simulation log: `build/vcs_sdf_async_warning_cleanup_gls/sim.log`.
- Async-cleaned timing-overlay run stdout: `remote_codex_jobs/sdf_async_warning_cleanup_20260519_210546/logs/sdf_async_warning_cleanup_run.stdout`.
- Normalization report: `build/vcs_sdf_async_warning_cleanup_gls/sky130_sdf_normalization_report.txt`.
- Original blocker summary: `remote_codex_jobs/sdf_power_closure_ascii_20260519_163744/artifacts/sdf_gls_blocker_summary.txt`.
- Prior blocker summary: `remote_codex_jobs/sdf_specify_timing_20260519_172238/final.md`.
- Latest SDF pathname mapping summary: `remote_codex_jobs/sdf_pathname_mapping_20260519_193830/final.md`.
- Latest SDF async warning cleanup summary: `remote_codex_jobs/sdf_async_warning_cleanup_20260519_210546/final.md`.

The timing-overlay run embeds Sky130 HS PDK specify blocks into generated
strength-specific behavioral models and adds local alias wires for PDK naming
mismatches such as `awake`/`AWAKE`, `cond0`/`COND0`, `cond1`/`COND1`,
`RESET_B_delayed`/`RESETB_delayed`, and `SET_B_delayed`/`SETB_delayed`.
It does not invent timing arcs or insert new timing checks. The opt-in
normalizer keeps the original exported SDF intact and rewrites only standalone
`A1N/A2N` condition tokens to `A1_N/A2_N` inside affected
`o2bb2ai/a2bb2oi/o2bb2a` `CELLTYPE` blocks. With
`POST_SYNTH_NORMALIZE_SKY130_SDF_ASYNC=1`, it also merges adjacent
`dfrtp/dfstp` async `RECOVERY`/`HOLD` records into the single `RECREM` form
present in the PDK specify blocks. The final normalization report shows
`changed_cells=4020`, `changed_lines=48240`, `A1N_to_A1_N=36180`,
`A2N_to_A2_N=36180`, and `async_recrem_pairs=14708`.

Normalized SDF GLS metrics:

```text
Cycles:         299745
RD_BYTES:       2260992
WR_BYTES:       32768
mean_abs_error: 0.001955
max_abs_error:  0.004405
row0_causal:    0.003906
>>> ALL TESTS PASSED <<<
```

The previous pathname and async reset/set annotation blockers are gone:
`SDFCOM_IANE=0`, `SDFCOM_TANE=0`, `SDFCOM_INF=0`, `SDFCOM_CFTC=0`,
`SDFCOM_NL=0`, and `WSUM=0`. Remaining compile warnings are
`SDFCOM_SWC=148`, `SDFCOM_IWSBA=55`, `SDFCOM_NDI=116`, `MDOTDS=5`,
`TFIPC=184`, `IPDW=3`, and `IDTS=2`; compile `Warning-=513`, `Error-=0`,
`Fatal=0`. The simulation logs contain no setup/hold/recovery/removal timing
violation messages.

## Activity Power

- Activity power scripts: `scripts/run_power_activity.sh`, `scripts/run_power_activity.tcl`.
- Command: `POWER_ACTIVITY_TAG=20260519_1654 bash scripts/run_power_activity.sh`.
- Result: PASS with annotation caveats.
- RTL simulation log: `build/vcs_power_activity_20260519_1654/sim.log`.
- VCD: `build/vcs_power_activity_20260519_1654/fa_system_tb.vcd`.
- SAIF: `build/dc_power_activity_20260519_1654/activity/fa_system_tb_dut.saif`.
- VCD-to-SAIF log: `build/dc_power_activity_20260519_1654/vcd2saif.log`.
- DC activity log: `build/dc_power_activity_20260519_1654/dc_power_activity.log`.
- Power report: `build/dc_power_activity_20260519_1654/reports/dc_power_activity.rpt`.
- Hierarchical power report: `build/dc_power_activity_20260519_1654/reports/dc_power_activity_hier.rpt`.

Activity power summary:

```text
Cell Internal Power  =   2.2902  W
Net Switching Power  =  19.4931 mW
Total Dynamic Power  =   2.3097  W
Cell Leakage Power   =  78.6975 uW
Total table row      =   2.3107e+03 mW
```

DC caveats in the report: 3 switching-activity conflicts, ignored constant-net
annotations, a clock toggle conflict where DC uses the annotated value, and
unannotated sequential cell outputs.

## Patch And Reports

- Continuous quality report: `remote_codex_jobs/continuous_quality_20260518_150847/final.md`.
- Verification completion report: `remote_codex_jobs/verification_completion_20260518_154615/final.md`.
- Post-completion polish status: `remote_codex_jobs/post_completion_polish_20260519_155538/status.md`.
- Post-completion polish final report: `remote_codex_jobs/post_completion_polish_20260519_155538/final.md`.
- Patch artifact: `remote_codex_jobs/post_completion_polish_20260519_155538/artifacts/cadence_new_post_completion_polish.patch`.
- SDF/power closure status: `remote_codex_jobs/sdf_power_closure_ascii_20260519_163744/status.md`.
- SDF/power closure final report: `remote_codex_jobs/sdf_power_closure_ascii_20260519_163744/final.md`.
- SDF specify timing GLS status: `remote_codex_jobs/sdf_specify_timing_20260519_172238/status.md`.
- SDF specify timing GLS final report: `remote_codex_jobs/sdf_specify_timing_20260519_172238/final.md`.
- SDF pathname mapping status: `remote_codex_jobs/sdf_pathname_mapping_20260519_193830/status.md`.
- SDF pathname mapping final report: `remote_codex_jobs/sdf_pathname_mapping_20260519_193830/final.md`.
- SDF async warning cleanup status: `remote_codex_jobs/sdf_async_warning_cleanup_20260519_210546/status.md`.
- SDF async warning cleanup final report: `remote_codex_jobs/sdf_async_warning_cleanup_20260519_210546/final.md`.
- UVM verification environment status: `remote_codex_jobs/uvm_verification_env_20260519_232113/status.md`.
- UVM verification environment final report: `remote_codex_jobs/uvm_verification_env_20260519_232113/final.md`.
- UVM verification environment patch: `remote_codex_jobs/uvm_verification_env_20260519_232113/artifacts/cadence_new_uvm_verification_env.patch`.
- Bonus UVM completion status: `remote_codex_jobs/bonus_uvm_completion_20260520_010220/status.md`.
- Bonus UVM completion final report: `remote_codex_jobs/bonus_uvm_completion_20260520_010220/final.md`.
- Bonus UVM completion patch: `remote_codex_jobs/bonus_uvm_completion_20260520_010220/artifacts/cadence_new_bonus_uvm_completion.patch`.
- Full bonus UVM completion status: `remote_codex_jobs/bonus_full_uvm_20260520_013839/status.md`.
- Full bonus UVM completion final report: `remote_codex_jobs/bonus_full_uvm_20260520_013839/final.md`.
- Full bonus UVM completion patch: `remote_codex_jobs/bonus_full_uvm_20260520_013839/artifacts/cadence_new_bonus_full_uvm.patch`.

## Remaining Notes

- Build directories are evidence outputs and are not packed by this checklist.
- Total code coverage is not 100%; the functional coverage groups are 100%.
- Bonus PASS claims are limited to features with RTL plus UVM scoreboard evidence.
  External BF16/FP16, Q6.10/Q4.12, INT8 Q4.4, and FP8 E4M3 modes are tensor
  I/O conversions around the internal Q8.8 compute core, not native FP
  arithmetic or packed bandwidth reduction. The S=512 claim is a compile-time
  `SEQ_LEN=512` bounded `VALID_LEN=260` test, not a full `VALID_LEN=512`
  runtime. The AXI4-Stream claim is a standalone ready/valid bridge smoke test,
  not attention-over-AXIS.
- The no-SDF gate simulation depends on functional Sky130 HS wrappers plus locally generated helper stubs under the build directory; it is useful evidence of netlist functional equivalence under the system TB.
- SDF timing GLS now produces passing system metrics with the opt-in normalized SDF/specify overlay. It is not a clean timing signoff run because residual annotation warnings remain (`SDFCOM_SWC`, `SDFCOM_IWSBA`, and `SDFCOM_NDI`), although the async reset/set `SDFCOM_CFTC` and `WSUM` blockers are eliminated.
- Activity-based power is now recorded from RTL VCD/SAIF and DC `read_saif`, but a fully mapped gate-level SAIF would be stronger evidence.
- Full DC timing/area optimization was not rerun after the bonus RTL extensions. A post-bonus check-only DC run successfully analyzed, elaborated, linked, and wrote `dc_check_design.rpt` with lint warnings; compile was intentionally skipped and the optional report tail was terminated after check-design evidence was generated.
