#!/bin/bash
SRC=/usr/synopsys/vcs-L-2016.06/linux64/lib
DST=/usr/synopsys/vcs-L-2016.06/lib
mkdir -p $DST
for f in $SRC/lib*.so; do
    bn=$(basename "$f")
    ln -sf "$f" "$DST/$bn" 2>/dev/null
done
echo "Linked $(ls $DST/lib*.so 2>/dev/null | wc -l) libraries"
ls $DST/lib*.so 2>/dev/null | head -5
