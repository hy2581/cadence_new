#!/usr/bin/env python3
import paramiko
import sys

def run_remote(cmd, timeout=60):
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect('117.50.81.212', username='ubuntu', password='0P89Q7e1hZLa62k5', timeout=15)
    stdin, stdout, stderr = ssh.exec_command(cmd, timeout=timeout)
    out = stdout.read().decode(errors='replace')
    err = stderr.read().decode(errors='replace')
    ssh.close()
    return out, err

# Create a test SV file and compile it
cmds = """
sudo docker exec synopsys_its bash -c '
export SNPSLMD_LICENSE_FILE=/usr/local/flexlm/licenses/license.dat
export VCS_HOME=/usr/synopsys/vcs-L-2016.06
cd /tmp
cat > test.sv << "EOF"
module test;
  initial begin
    $display("VCS working!");
    $finish;
  end
endmodule
EOF
vcs -full64 -sverilog test.sv -o simv_test 2>&1 | tail -20
echo "=== RUN ==="
./simv_test 2>&1 | tail -10
'
"""

out, err = run_remote(cmds.strip())
print("STDOUT:", out)
if err:
    print("STDERR:", err)
