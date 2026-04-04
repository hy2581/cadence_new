import paramiko
import os

HOST = 'frp-dog.com'
PORT = 56557
USER = 'hy258'
PASS = 'haoyu123'
LOCAL_BASE = os.path.dirname(os.path.abspath(__file__))
REMOTE_BASE = '/home/hy258/cadence'

FILES = [
    'submission/baseline/tb/agents/axi4_mem_agent/axi4_mem_agent.sv',
    'submission/baseline/tb/agents/axi4_lite_agent/axi4_lite_driver.sv',
    'submission/baseline/tb/uvm_env/fa_coverage.sv',
    'submission/baseline/tb/uvm_env/fa_env.sv',
    'submission/baseline/tb/uvm_env/fa_reg_model.sv',
    'submission/baseline/tb/sequences/fa_sequences.sv',
    'submission/baseline/tb/tests/fa_tests.sv',
    'submission/baseline/tb/tb_top/fa_tb_top.sv',
    'submission/scripts/run_uvm_all.sh',
    'submission/README.md',
    'submission/docker_run_all.sh',
    'submission/vcs_fopen_fix.c',
]

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect(HOST, port=PORT, username=USER, password=PASS, timeout=30)
sftp = ssh.open_sftp()

for f in FILES:
    local = os.path.join(LOCAL_BASE, f)
    remote = f'{REMOTE_BASE}/{f}'
    remote_dir = os.path.dirname(remote)
    parts = remote_dir.split('/')
    for i in range(1, len(parts) + 1):
        d = '/'.join(parts[:i])
        if not d:
            continue
        try:
            sftp.stat(d)
        except FileNotFoundError:
            sftp.mkdir(d)
    sftp.put(local, remote)
    print(f'  OK: {f}')

sftp.close()
ssh.close()
print('All files uploaded.')
