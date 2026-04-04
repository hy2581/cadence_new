import paramiko
import sys

def run_ssh(cmd):
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect('192.168.5.154', username='hy258', password='haoyu123', timeout=10)
    stdin, stdout, stderr = ssh.exec_command(cmd, timeout=120)
    out = stdout.read().decode()
    err = stderr.read().decode()
    if out:
        print(out)
    if err:
        print("STDERR:", err)
    ssh.close()

if __name__ == '__main__':
    run_ssh(' '.join(sys.argv[1:]))
