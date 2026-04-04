#!/bin/bash
export SNPSLMD_LICENSE_FILE=27000@localhost
cd /work/cadence/submission

VCS1=/usr/synopsys/vcs-L-2016.06/linux64/bin/vcs1
VCSHOME=/usr/synopsys/vcs-L-2016.06

$VCS1 -Mcc=gcc -Mcplusplus=g++ \
  "-Mcfl= -pipe -fPIC -O -I${VCSHOME}/include " \
  "-Mxcflags= -pipe -fPIC -I${VCSHOME}/include" \
  "-Mldflags= -rdynamic " \
  -Mout=/tmp/fa_min \
  "-Mobjects= ${VCSHOME}/linux64/lib/libvirsim.so ${VCSHOME}/linux64/lib/liberrorinf.so ${VCSHOME}/linux64/lib/libsnpsmalloc.so " \
  -Msaverestoreobj=${VCSHOME}/linux64/lib/vcs_save_restore_new.o \
  "-Msyslibs=-ldl " \
  -full64 -timescale=1ns/1ps +define+SIMULATION \
  -o /tmp/fa_min \
  -picarchive -sverilog -gen_obj \
  +incdir+baseline/rtl/include \
  baseline/rtl/exp_lut_rom.sv \
  -P ${VCSHOME}/linux64/lib/vcsdstub.tab

echo "Exit code: $?"
