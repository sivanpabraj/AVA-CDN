#!/usr/bin/env python3
"""Deploy avashop.online CDN + Xray inbound to Germany server."""
import os
import sys
import time
import uuid
import json
import paramiko

HOST = "49.13.6.108"
USER = "root"
PASSWORD = os.environ.get("AVA_SSH_PASS", "ava74826+++===")
REPO_URL = "https://github.com/sivanpabraj/AVA-CDN.git"
BRANCH = "cursor/germany-cdn-origin-setup-132b"
INSTALL_DIR = "/opt/ava-cdn/avashop.online"

# Inbound design
INBOUND_UUID = str(uuid.uuid4())
GRPC_SERVICE = "grpc-avashop"
CDN_DOMAIN = "de.avashop.online"
TUNNEL_DOMAIN = "tunnel.avashop.online"
XRAY_PORT = 2096


def run(ssh, cmd, timeout=300):
    print(f"\n>>> {cmd[:120]}{'...' if len(cmd) > 120 else ''}")
    stdin, stdout, stderr = ssh.exec_command(cmd, timeout=timeout)
    out = stdout.read().decode()
    err = stderr.read().decode()
    code = stdout.channel.recv_exit_status()
    if out.strip():
        print(out.strip()[:3000])
    if err.strip() and code != 0:
        print("STDERR:", err.strip()[:1000])
    return code, out, err


def main():
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    print(f"Connecting to {HOST}...")
    ssh.connect(HOST, username=USER, password=PASSWORD, timeout=30)
    print("Connected.")

    # System info
    run(ssh, "uname -a && cat /etc/os-release | head -3")

    # Clone or update repo
    code, _, _ = run(ssh, f"test -d /root/AVA-CDN/.git")
    if code != 0:
        run(ssh, f"cd /root && rm -rf AVA-CDN && git clone -b {BRANCH} {REPO_URL}")
    else:
        run(ssh, f"cd /root/AVA-CDN && git fetch && git checkout {BRANCH} && git pull")

    # Run CDN deploy
    run(ssh, "cd /root/AVA-CDN && bash setup-avashop.sh", timeout=600)

    # Deploy 3x-ui + inbound
    run(ssh, "cd /root/AVA-CDN && bash setup-avashop.sh --with-inbound", timeout=600)

    # Save inbound info locally
    code, out, _ = run(ssh, f"cat {INSTALL_DIR}/inbound.json 2>/dev/null || echo '{{}}'")
    print("\n=== INBOUND CONFIG ===")
    print(out)

    ssh.close()
    print("\nDeploy finished.")


if __name__ == "__main__":
    main()
