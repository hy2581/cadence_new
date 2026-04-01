#!/usr/bin/env python3
import sys
path = '/usr/synopsys/vcs-mx/O-2018.09-SP2/etc/uvm-1.2/dpi/uvm_hdl_vcs.c'
with open(path, 'rb') as f:
    data = f.read()
data = data.replace(b'\xe2\x80\x9c', b'\x22')
data = data.replace(b'\xe2\x80\x9d', b'\x22')
data = data.replace(b'\xe2\x80\x99', b'\x27')
with open(path, 'wb') as f:
    f.write(data)
print('Fixed Unicode characters in UVM DPI source')
