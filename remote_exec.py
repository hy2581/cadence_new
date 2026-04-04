import paramiko
import sys
import time

HOST = 'frp-dog.com'
PORT = 56557
USER = 'hy258'
PASS = 'haoyu123'

def run_ssh(cmd, timeout=300):
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(HOST, port=PORT, username=USER, password=PASS, timeout=30)
    stdin, stdout, stderr = ssh.exec_command(cmd, timeout=timeout)
    out = stdout.read().decode(errors='replace')
    err = stderr.read().decode(errors='replace')
    exit_code = stdout.channel.recv_exit_status()
    ssh.close()
    if out:
        print(out)
    if err:
        print("STDERR:", err)
    print(f"[EXIT CODE: {exit_code}]")
    return out, err, exit_code

if __name__ == '__main__':
    cmd = ' '.join(sys.argv[1:]) if len(sys.argv) > 1 else 'echo hello'
    run_ssh(cmd)
