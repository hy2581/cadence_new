import paramiko
import os
import sys

def upload_file(local_path, remote_path):
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect('192.168.5.154', username='hy258', password='haoyu123', timeout=10)
    sftp = ssh.open_sftp()
    
    remote_dir = os.path.dirname(remote_path)
    try:
        sftp.stat(remote_dir)
    except FileNotFoundError:
        parts = remote_dir.split('/')
        for i in range(1, len(parts) + 1):
            d = '/'.join(parts[:i])
            if not d:
                continue
            try:
                sftp.stat(d)
            except FileNotFoundError:
                sftp.mkdir(d)
    
    sftp.put(local_path, remote_path)
    print(f"Uploaded: {local_path} -> {remote_path}")
    sftp.close()
    ssh.close()

def upload_dir(local_dir, remote_dir):
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect('192.168.5.154', username='hy258', password='haoyu123', timeout=10)
    sftp = ssh.open_sftp()
    
    for root, dirs, files in os.walk(local_dir):
        for f in files:
            local_path = os.path.join(root, f)
            rel = os.path.relpath(local_path, local_dir).replace('\\', '/')
            remote_path = f"{remote_dir}/{rel}"
            
            remote_sub = os.path.dirname(remote_path).replace('\\', '/')
            parts = remote_sub.split('/')
            for i in range(1, len(parts) + 1):
                d = '/'.join(parts[:i])
                if not d:
                    continue
                try:
                    sftp.stat(d)
                except FileNotFoundError:
                    sftp.mkdir(d)
            
            sftp.put(local_path, remote_path)
            print(f"  {rel}")
    
    sftp.close()
    ssh.close()
    print(f"Done: uploaded {local_dir} -> {remote_dir}")

if __name__ == '__main__':
    if len(sys.argv) == 3:
        src, dst = sys.argv[1], sys.argv[2]
        if os.path.isdir(src):
            upload_dir(src, dst)
        else:
            upload_file(src, dst)
    else:
        print("Usage: python sftp_upload.py <local_path> <remote_path>")
