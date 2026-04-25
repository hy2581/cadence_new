# Synopsys 2025 setup

This project is configured for the Synopsys 2025 installation on the remote
server reached with:

```bash
ssh -p 56557 hy258@frp-dog.com
```

The expected tool locations are:

```bash
VCS_HOME=/eda/synopsys2025/vcs/X-2025.06
SYNOPSYS=/eda/synopsys2025/syn/X-2025.06-SP4
SNPSLMD_LICENSE_FILE=/eda/license/Synopsys.dat
LM_LICENSE_FILE=/eda/license/Synopsys.dat
TSMCHOME=~/lib_new/TSMCHOME
```

The helper script `scripts/synopsys2025_env.sh` sets these defaults when the
paths exist, and leaves user-provided overrides untouched.

The TSMC 12nm library defaults are in `scripts/tsmc12_env.sh`. On the remote
server it selects this slow-corner target library by default:

```text
~/lib_new/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn12ffcllbwp6t16p96cpd_120a/tcbn12ffcllbwp6t16p96cpdssgnp0p72v125c.db
```

Use another corner by overriding `TSMC12_CORNER` or `DC_TARGET_LIB`, for example:

```bash
TSMC12_CORNER=tt0p8v25c bash scripts/run_dc.sh
DC_TARGET_LIB=/path/to/other_corner.db bash scripts/run_dc.sh
```

## VCS system test

```bash
cd ~/cadence_new
source scripts/synopsys2025_env.sh
bash scripts/run_system_tb.sh
```

Outputs are written to:

```text
build/vcs_system_tb/compile.log
build/vcs_system_tb/sim.log
```

To run in the background:

```bash
nohup bash scripts/run_system_tb.sh > build/vcs_system_tb.nohup.log 2>&1 &
```

## Design Compiler synthesis

The default flow uses the TSMC 12nm `.db` discovered under `TSMCHOME`:

```bash
cd ~/cadence_new
source scripts/synopsys2025_env.sh
source scripts/tsmc12_env.sh
bash scripts/run_dc.sh
```

If no TSMC12 library is found, `scripts/run_dc.tcl` falls back to Synopsys
sample libraries such as `class.db`. That mode is useful for checking the DC
2025 flow, but its reports are not valid final QoR data.

Outputs are written to:

```text
build/dc/dc_shell.log
build/dc/reports/
build/dc/netlist/
```

To run in the background:

```bash
nohup bash scripts/run_dc.sh > build/dc.nohup.log 2>&1 &
```
