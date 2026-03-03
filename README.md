# 🚀 Ultra Light SOCKS5 Proxy generator script

[![Bash](https://img.shields.io/badge/Language-Bash%2FAsh-4EAA25.svg)](#)
[![OS](https://img.shields.io/badge/OS-Debian%20%7C%20Ubuntu%20%7C%20Alpine-A81D33.svg)](#)
[![RAM](https://img.shields.io/badge/RAM-64MB%2B-blue.svg)](#)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](#)

A lightning-fast, zero-bloat script to automatically install, secure, and manage a SOCKS5 proxy (Dante) on Debian, Ubuntu, and Alpine Linux servers. 

Designed specifically for **extreme low-end VPS environments (64MB/128MB RAM)** and LXC containers, this script strips away unnecessary overhead, features built-in SSRF protection, and dynamically handles out-of-memory (OOM) errors during installation. Perfect for those looking to maximize the utility of cheap micro-VPS deals without crashing their nodes.

---

## ✨ Key Features

### 🪶 Built for the Lowest Specs (Low End Ready)
* **Zero Log-Bloat:** Configured to output strictly to `stderr` with no persistent log files, saving your precious 5GB/10GB disk space.
* **Intelligent Auto-Swap (Debian/Ubuntu):** Automatically detects servers with <512MB RAM and temporarily allocates a 512MB swap file during installation. This prevents the Linux OOM-killer from terminating the package manager on tiny nodes, and cleanly removes the swap once finished.
* **Debian 13 (Trixie) Fallback:** Automatically detects missing packages in newer Debian branches and pulls the stable Bookworm `.deb` fallback seamlessly.
* **Alpine Native:** A dedicated, hyper-optimized version written specifically for Alpine's `apk` package manager and `OpenRC` init system.

### 🛡️ Hardened Security out of the Box
* **SSRF Protection:** Pre-configured with strict blocklists to prevent Server-Side Request Forgery. Users cannot use the proxy to access your server's loopback address (`127.0.0.0/8`), private internal networks, or cloud metadata endpoints.
* **True User Isolation:** * *Debian/Ubuntu:* Uses `libpam-pwdfile` to authenticate against a custom `.passwd` file. Proxy users **do not** have system accounts.
  * *Alpine:* Uses strictly locked-down system users (`/sbin/nologin` shell, no home directory) ensuring proxy users can never SSH into your server.
* **Secure Hashing:** All generated passwords are encrypted using strong SHA-512 hashing (Debian) or standard `chpasswd` (Alpine) before being stored.

### ⚙️ Interactive Dashboard Management
Launch the script at any time to access the persistent management menu:
* **Add/Remove Users:** Instantly provision new users with securely generated 20-character alphanumeric passwords.
* **Change Global Port:** Migrate your entire proxy service to a new port on the fly. The script automatically updates Dante configurations and handles UFW/iptables firewall rules.
* **List Users:** Quickly view all active proxy accounts.

---

## 🚀 Quick Install

Run the command below for your OS to download and launch the manager instantly. Enter your `sudo` password if prompted.

### 🐧 For Debian & Ubuntu
```bash
wget -qO socks5.sh https://raw.githubusercontent.com/mathewskdaniel/selfhostedSocks5/main/socks5.sh && sudo bash socks5.sh
```

### ⛰️ For Alpine Linux
```bash
wget -qO alpinesocks5.sh https://raw.githubusercontent.com/mathewskdaniel/selfhostedSocks5/main/alpinesocks5.sh && sudo ash alpinesocks5.sh
```
*(Note: If you are running as `root` in a minimal container without sudo, simply remove `sudo` from the command).*

---

## 🖥️ Compatibility
* **Debian:** 11+
* **Ubuntu:** 20.04+
* **Alpine:** 3.x+
* **Architecture:** AMD64 (x86_64) and ARM64 (aarch64)
* **Virtualization:** KVM, OpenVZ, and LXC containers.

---

## 📸 Menu Preview

```text
╔══════════════════════════════════╗
║      SOCKS5 Master Manager       ║
╠══════════════════════════════════╣
║ Status: Running                  ║
║ IP:   192.168.69.42              ║
║ Port: 44321                      ║
╠══════════════════════════════════╣
║ 1) List Users                    ║
║ 2) Add New User                  ║
║ 3) Remove a User                 ║
║ 4) Change Global Port            ║
║ 5) Full Uninstall                ║
║ 6) Exit                          ║
╚══════════════════════════════════╝
```

## ⚠️ Disclaimer
This script generates irreversible password hashes. When you add a new proxy user, **save the provided password immediately**. It cannot be recovered from the server once the screen clears.

## 📄 License
MIT License. Feel free to fork, modify, and deploy across your fleets!
