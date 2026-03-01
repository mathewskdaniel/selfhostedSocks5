# 🚀 Ultra Light SOCKS5 Proxy generator script

[![Bash](https://img.shields.io/badge/Language-Bash-4EAA25.svg)](#)
[![OS](https://img.shields.io/badge/OS-Debian%20%7C%20Ubuntu-A81D33.svg)](#)
[![RAM](https://img.shields.io/badge/RAM-64MB%2B-blue.svg)](#)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](#)

A lightning-fast, zero-bloat bash script to automatically install, secure, and manage a SOCKS5 proxy (Dante) on Debian and Ubuntu servers. 

Designed specifically for **extreme low-end VPS environments (64MB/128MB RAM)** and LXC containers, this script strips away unnecessary overhead, features built-in SSRF protection, and dynamically handles out-of-memory (OOM) errors during installation. Perfect for those looking to maximize the utility of cheap micro-VPS deals without crashing their nodes.



---

## ✨ Key Features

### 🪶 Built for the Lowest Specs (Low End Ready)
* **Zero Log-Bloat:** Configured to output strictly to `stderr` with no persistent log files, saving your precious 5GB/10GB disk space.
* **Intelligent Auto-Swap:** Automatically detects servers with <512MB RAM and temporarily allocates a 512MB swap file during installation. This prevents the Linux OOM-killer from terminating the package manager on tiny nodes, and cleanly removes the swap once finished.
* **Debian 13 (Trixie) Fallback:** Automatically detects missing packages in newer Debian branches and pulls the stable Bookworm `.deb` fallback seamlessly.

### 🛡️ Hardened Security out of the Box
* **SSRF Protection:** Pre-configured with strict blocklists to prevent Server-Side Request Forgery. Users cannot use the proxy to access your server's loopback address (`127.0.0.0/8`), private internal networks, or cloud metadata endpoints.
* **True User Isolation:** Uses `libpam-pwdfile` to authenticate users against a custom `.passwd` file. Proxy users **do not** have system accounts and cannot SSH into your server.
* **SHA-512 Hashing:** All generated passwords are encrypted using strong SHA-512 hashing before being stored.

### ⚙️ Interactive Dashboard Management
Launch the script at any time to access the persistent management menu:
* **Add/Remove Users:** Instantly provision new users with securely generated 20-character alphanumeric passwords.
* **Change Global Port:** Migrate your entire proxy service to a new port on the fly. The script automatically updates Dante configurations and handles UFW firewall rules.
* **List Users:** Quickly view all active proxy accounts.

---

## 🚀 Quick Install

Run the below command to download and launch the manager instantly. Enter sudo pasword if prompted.

```bash
wget -qO socks5.sh https://raw.githubusercontent.com/mathewskdaniel/selfhostedSocks5/main/socks5.sh && sudo bash socks5.sh
