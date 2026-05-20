# Linux Administration — Network Infrastructure & Web Hosting
## Agri-Tech Project: DNS + LAMP + FTP + Routing + NAT

> **ISGA Marrakech — Level 2CI-ISI** — Prof. Lahcen AITIBOUREK
> Student: Yassine Boucham
> Date: 19/05/2026

---
## Restart the ens33 network interface
Virtual network
![reseau_virtuel](./screenshots/reseau_virtuel.PNG)
Network adapter
![Carte_reseau](./screenshots/Carte_reseau.PNG)

- Method 1: using ip (simple)
```
sudo ip link set ens33 down
sudo ip link set ens33 up
```
- Method 2: using ifdown and ifup
```
sudo ifdown ens33
sudo ifup ens33
```
- Method 3: restart the entire network service
> On classic Debian:
```
sudo systemctl restart networking
```
> If using systemd-networkd:
```
sudo systemctl restart systemd-networkd
```

## Project Diagram
![Project Diagram](./screenshots/architecture_partie0_partie1%20(1).svg)

## Table of Contents

### 🔧 Part 0 — Network Infrastructure (Prerequisites)
- [Target network architecture](#target-network-architecture)
- [Phase 1 — Machine identification](#phase-1--machine-identification-hostnamectl)
- [Phase 2 — systemd-networkd network configuration](#phase-2--systemd-networkd-network-configuration)
- [Phase 3 — Inter-VLAN routing and NAT nftables](#phase-3--inter-vlan-routing-and-nat-nftables)
- [Phase 4 — Validation and final tests](#phase-4--validation-and-final-tests)

### 🌐 Part 1 — Web Services (DNS + LAMP + FTP)
1. [Introduction](#introduction)
2. [Step 1 — Server preparation](#step-1--server-preparation)
3. [Step 2 — DNS with BIND9](#step-2--dns-installation-and-configuration-bind9)
4. [Step 3 — LAMP installation](#step-3--lamp-installation)
5. [Step 4 — FTP installation (vsftpd)](#step-4--ftp-installation-vsftpd)
6. [Step 5 — WordPress deployment (name.blog)](#step-5--wordpress-deployment-nameblog)
7. [Step 6 — Drupal deployment (firstname.site)](#step-6--drupal-deployment-firstnamesite)
8. [Final verification](#final-verification)
9. [Conclusion](#conclusion)

---



# 🔧 Part 0 — Network Infrastructure

> ⚠️ **This part must be completed BEFORE installing any services.**
> It configures the base network (routing, NAT) on which everything else relies.

## Target Network Architecture

```
                        INTERNET (WAN)
                             │
                    ┌────────▼────────┐
                    │   srv-linux     │
                    │  ens33: DHCP    │  ← NAT / Masquerade
                    │  ens34: 10.10.10.254
                    │  ens35: 20.20.20.254
                    └──────┬──────┬───┘
                           │      │
               ┌───────────▼┐    ┌▼────────────┐
               │  Admin LAN │    │   IoT LAN   │
               │10.10.10.11 │    │ 20.20.20.22 │
               │client-admin│    │ client-iot  │
               └────────────┘    └─────────────┘
```

| Machine       | Interface | IP Address       | Role              |
|---------------|-----------|------------------|-------------------|
| srv-linux     | ens33     | DHCP (NAT WAN)   | Router / Server   |
| srv-linux     | ens34     | 10.10.10.254/24  | Admin LAN Gateway |
| srv-linux     | ens35     | 20.20.20.254/24  | IoT LAN Gateway   |
| client-admin  | ens33     | 10.10.10.11/24   | Admin Client      |
| client-iot    | ens33     | 20.20.20.22/24   | IoT Client        |

---

## Phase 1 — Machine Identification (hostnamectl)

> 💡 **Why hostnamectl?** Unlike editing `/etc/hostname` manually, `hostnamectl` applies the change immediately without a reboot, updates the name in systemd, and ensures consistency across the entire system environment.

### On srv-linux (router)

```bash
hostnamectl set-hostname srv-linux
sudo nano /etc/hosts
```

In `/etc/hosts`, modify the `127.0.1.1` line:

```
127.0.1.1   srv-linux
```

### On client-admin

```bash
hostnamectl set-hostname client-admin
sudo nano /etc/hosts
# Modify: 127.0.1.1   client-admin
```

### On client-iot

```bash
hostnamectl set-hostname client-iot
sudo nano /etc/hosts
# Modify: 127.0.1.1   client-iot
```

Verify on each machine:

```bash
hostnamectl status
```

> 📸 **Proof #1** — On `client-iot`, output of `hostnamectl status`
> `[ Insert your screenshot here ]`

---

## Phase 2 — Network Configuration (systemd-networkd)

> 💡 **ifupdown vs systemd-networkd**: `ifupdown` is the old Debian network configuration system, based on shell scripts and the `/etc/network/interfaces` file. It is static and requires restarts. `systemd-networkd` is the modern system integrated into systemd: it manages configuration declaratively (`.network` files), responds dynamically to hardware changes, and integrates natively with `resolved` for DNS. It is the Debian 13 standard.

### Initial cleanup (on all 3 machines)

```bash
systemctl stop networking
systemctl disable networking
mv /etc/network/interfaces /etc/network/interfaces.backup
systemctl enable systemd-networkd
systemctl start systemd-networkd
```
-> You can check if systemd-networkd is being used with these commands:
```
    systemctl status systemd-networkd
```
- If it is active, you will see something like:
* Active: active (running)

-> You can also verify which service manages your interfaces:
```
    networkctl
```
- If systemd-networkd is managing the network, it will list your interfaces with states like:
* IDX LINK  TYPE     OPERATIONAL    SETUP
  2 ens33   ether    routable       configured

-> Another useful check:
```
    systemctl is-enabled systemd-networkd
```
- Results:
* enabled → starts automatically at boot
* disabled → not enabled
* masked → blocked from starting

### srv-linux router configuration

Create the 3 files in `/etc/systemd/network/`:

**File `10-wan.network`** (WAN interface toward the Internet):

```ini
[Match]
Name=ens33

[Network]
DHCP=ipv4
```

**File `20-lan-admin.network`** (Admin LAN):

```ini
[Match]
Name=ens34

[Network]
Address=10.10.10.254/24
IPForward=ipv4
```

**File `30-lan-iot.network`** (IoT LAN):

```ini
[Match]
Name=ens35

[Network]
Address=20.20.20.254/24
IPForward=ipv4
```

> 💡 **IPForward=ipv4** replaces the command `sysctl -w net.ipv4.ip_forward=1`. Forwarding is enabled directly in the systemd-networkd configuration, persistently and without editing `/etc/sysctl.conf`.

```bash
systemctl restart systemd-networkd
networkctl status
```

> 📸 **Proof #2** — `networkctl status` on srv-linux showing all 3 interfaces as "configured"
> `[ Insert your screenshot here ]`

### client-admin configuration

Create `/etc/systemd/network/10-lan.network`:

```ini
[Match]
Name=ens33

[Network]
Address=10.10.10.11/24
Gateway=10.10.10.254
DNS=8.8.8.8
```

```bash
systemctl restart systemd-networkd
```

### client-iot configuration

Create `/etc/systemd/network/10-lan.network`:

```ini
[Match]
Name=ens33

[Network]
Address=20.20.20.22/24
Gateway=20.20.20.254
DNS=8.8.8.8
```

```bash
systemctl restart systemd-networkd
```

> 📸 **Proof #3** — On `client-admin`, output of `networkctl status ens33` (IP + Gateway visible)
> `[ Insert your screenshot here ]`

---

## Phase 3 — Inter-VLAN Routing and NAT (nftables)

> 💡 `nftables` is the successor to `iptables` on Debian 13. It unifies IPv4/IPv6 rule management in a single, more readable and more performant framework.

On **srv-linux**:

```bash
# 1. Create the NAT table for IPv4
nft add table ip nat

# 2. Create the postrouting chain
nft add chain ip nat postrouting \{ type nat hook postrouting priority 100 \; \}

# 3. Add the Masquerade rule on the WAN interface
nft add rule ip nat postrouting oifname "ens33" masquerade

# 4. Verify the configuration
nft list table ip nat
```

Expected output:

```
table ip nat {
    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        oifname "ens33" masquerade
    }
}
```

> 📸 **Proof #4** — Output of `nft list table ip nat` with the masquerade rule
> `[ Insert your screenshot here ]`

---

## Phase 4 — Validation and Final Tests

From **client-admin**, test the complete architecture:

```bash
# Test 1: Inter-VLAN routing (client-admin → client-iot)
ping -c 2 20.20.20.22

# Test 2: NAT and DNS resolution (Internet access)
ping -c 2 google.com
```

> 📸 **Proof #5** — Both pings successful from `client-admin` (inter-VLAN + Internet)
> `[ Insert your screenshot here ]`

---

---

# 🌐 Part 1 — Web Services (DNS + LAMP + FTP)

## Introduction

Once the network infrastructure from Part 0 is operational, this part installs and configures web services on **srv-linux**:

- **DNS (BIND9)** — name resolution for 2 domains
- **LAMP** — Apache web server + MySQL + PHP
- **FTP (vsftpd)** — file transfer from Windows
- **WordPress** on `name.blog`
- **Drupal** on `firstname.site`

> 💡 Environment: Debian 13 / Ubuntu Server — VMware — Prof. Lahcen AITIBOUREK
> 🔗 All commands are executed on **srv-linux** (10.10.10.254 / 20.20.20.254)

---

## Step 1 — Server Preparation

### 1.1 System update

Before any installation, update the packages:

```bash
sudo apt update
sudo apt upgrade -y
```

> 📸 **Screenshot 1** — Output of `apt update` / `apt upgrade`
> `[ Insert your screenshot here ]`

---

### 1.2 Hostname configuration

Set the server name with `hostnamectl`:

```bash
sudo hostnamectl set-hostname srv-linux
hostnamectl
```

> 📸 **Screenshot 2** — Output of the `hostnamectl` command
> `[ Insert your screenshot here ]`

---

### 1.3 Network configuration (systemd-networkd)

Configure network interfaces in `/etc/netplan/` or via `systemd-networkd` depending on your environment. Verify the IP address:

```bash
ip addr show
```

> 📸 **Screenshot 3** — Output of `ip addr show` (interfaces and IP addresses)
> `[ Insert your screenshot here ]`

---

## Step 2 — DNS Installation and Configuration (BIND9)

### 2.1 BIND9 installation

```bash
sudo apt install bind9 bind9utils bind9-doc -y
sudo systemctl status bind9
```

> 📸 **Screenshot 4** — BIND9 installed and service active (green status)
> `[ Insert your screenshot here ]`

---

### 2.2 Forward zone — name.blog

Declare the zone in `/etc/bind/named.conf.local`:

```
zone "name.blog" {
    type master;
    file "/etc/bind/db.name.blog";
};
```

Create the zone file `/etc/bind/db.name.blog`:

```
$TTL 604800
@   IN  SOA  srv-linux.name.blog. admin.name.blog. (
              2024010101 604800 86400 2419200 604800 )
@       IN  NS   srv-linux.name.blog.
srv-linux IN A   192.168.1.10
@       IN  A    192.168.1.10
www     IN  CNAME @
ftp     IN  CNAME @
mail    IN  CNAME @
```

> 📸 **Screenshot 5** — Contents of the `db.name.blog` file
> `[ Insert your screenshot here ]`

---

### 2.3 Forward zone — firstname.site

Repeat the same operation for `firstname.site` (Drupal) in `named.conf.local` and create `db.firstname.site` with the same structure.

> 📸 **Screenshot 6** — Contents of the `db.firstname.site` file
> `[ Insert your screenshot here ]`

---

### 2.4 Reverse zone (PTR)

Declare the reverse zone in `named.conf.local`:

```
zone "1.168.192.in-addr.arpa" {
    type master;
    file "/etc/bind/db.192";
};
```

File `/etc/bind/db.192`:

```
$TTL 604800
@   IN  SOA  srv-linux.name.blog. admin.name.blog. (
              2024010101 604800 86400 2419200 604800 )
@   IN  NS   srv-linux.name.blog.
10  IN  PTR  srv-linux.name.blog.
```

> 📸 **Screenshot 7** — Contents of the `db.192` file (reverse zone)
> `[ Insert your screenshot here ]`

---

### 2.5 BIND9 verification and restart

```bash
sudo named-checkconf
sudo named-checkzone name.blog /etc/bind/db.name.blog
sudo named-checkzone firstname.site /etc/bind/db.firstname.site
sudo systemctl restart bind9
```

> 📸 **Screenshot 8** — `named-checkconf` and `named-checkzone` with no errors
> `[ Insert your screenshot here ]`

---

### 2.6 DNS resolution test

```bash
nslookup name.blog 127.0.0.1
nslookup www.name.blog 127.0.0.1
nslookup ftp.name.blog 127.0.0.1
```

> 📸 **Screenshot 9** — `nslookup` results for `name.blog` and `firstname.site`
> `[ Insert your screenshot here ]`

---

## Step 3 — LAMP Installation

### 3.1 Apache2

```bash
sudo apt install apache2 -y
sudo systemctl enable apache2
sudo systemctl status apache2
```

> 📸 **Screenshot 10** — Apache2 active (green status)
> `[ Insert your screenshot here ]`

---

### 3.2 MySQL / MariaDB

```bash
sudo apt install mysql-server -y
sudo mysql_secure_installation
```

> 📸 **Screenshot 11** — `mysql_secure_installation` completed
> `[ Insert your screenshot here ]`

Create the databases for WordPress and Drupal:

```sql
sudo mysql -u root -p

CREATE DATABASE wordpress_db;
CREATE USER 'wp_user'@'localhost' IDENTIFIED BY 'password';
GRANT ALL PRIVILEGES ON wordpress_db.* TO 'wp_user'@'localhost';

CREATE DATABASE drupal_db;
CREATE USER 'drupal_user'@'localhost' IDENTIFIED BY 'password2';
GRANT ALL PRIVILEGES ON drupal_db.* TO 'drupal_user'@'localhost';

FLUSH PRIVILEGES;
EXIT;
```

> 📸 **Screenshot 12** — WordPress and Drupal databases created
> `[ Insert your screenshot here ]`

---

### 3.3 PHP

```bash
sudo apt install php php-mysql libapache2-mod-php -y
sudo apt install php-curl php-gd php-mbstring php-xml php-zip php-intl -y
php -v
```

> 📸 **Screenshot 13** — PHP version displayed (`php -v`)
> `[ Insert your screenshot here ]`

---

### 3.4 PHP test

```bash
echo "<?php phpinfo(); ?>" | sudo tee /var/www/html/info.php
# Open http://192.168.1.10/info.php in the browser
sudo rm /var/www/html/info.php
```

> 📸 **Screenshot 14** — `phpinfo()` page visible in the browser
> `[ Insert your screenshot here ]`

---

## Step 4 — FTP Installation (vsftpd)

### 4.1 Installation

```bash
sudo apt install vsftpd -y
sudo systemctl status vsftpd
```

> 📸 **Screenshot 15** — vsftpd installed and active
> `[ Insert your screenshot here ]`

---

### 4.2 Configuration /etc/vsftpd.conf

Edit the configuration file to enable writing:

```bash
sudo nano /etc/vsftpd.conf
```

Lines to modify:

```
write_enable=YES
local_enable=YES
chroot_local_user=YES
allow_writeable_chroot=YES
```

```bash
sudo systemctl restart vsftpd
```

> 📸 **Screenshot 16** — `vsftpd.conf` file with modified options
> `[ Insert your screenshot here ]`

---

### 4.3 Connection from Windows with FileZilla

| Parameter  | Value               |
|------------|---------------------|
| Host       | `192.168.1.10`      |
| Port       | `21`                |
| Protocol   | FTP                 |
| Username   | your_linux_user     |

Transfer the `wordpress.zip` file to `/var/www/html/` on the server.

> 📸 **Screenshot 17** — FileZilla connected, transferring `wordpress.zip`
> `[ Insert your screenshot here ]`

---

## Step 5 — WordPress Deployment (name.blog)

### 5.1 Extract WordPress

```bash
cd /var/www/html
sudo unzip wordpress.zip -d wordpress
sudo chown -R www-data:www-data wordpress/
sudo chmod -R 755 wordpress/
```

> 📸 **Screenshot 18** — `wordpress.zip` extracted successfully
> `[ Insert your screenshot here ]`

---

### 5.2 Apache Virtual Host for name.blog

Create `/etc/apache2/sites-available/name.blog.conf`:

```apache
<VirtualHost *:80>
    ServerName name.blog
    ServerAlias www.name.blog
    DocumentRoot /var/www/html/wordpress
    <Directory /var/www/html/wordpress>
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
```

```bash
sudo a2ensite name.blog.conf
sudo a2enmod rewrite
sudo systemctl reload apache2
```

> 📸 **Screenshot 19** — `name.blog` site enabled, Apache reloaded
> `[ Insert your screenshot here ]`

---

### 5.3 WordPress configuration

Open `http://name.blog` in the browser and follow the WordPress installation wizard (database name, username, password).

> 📸 **Screenshot 20** — WordPress installation page in the browser
> `[ Insert your screenshot here ]`

> 📸 **Screenshot 21** — WordPress installed, dashboard accessible
> `[ Insert your screenshot here ]`

---

## Step 6 — Drupal Deployment (firstname.site)

### 6.1 Download and extract

```bash
cd /var/www/html
sudo wget https://www.drupal.org/download-latest/zip -O drupal.zip
sudo unzip drupal.zip -d drupal
sudo chown -R www-data:www-data drupal/
sudo chmod -R 755 drupal/
```

> 📸 **Screenshot 22** — Drupal extracted to `/var/www/html/drupal`
> `[ Insert your screenshot here ]`

---

### 6.2 Apache Virtual Host for firstname.site

Create `/etc/apache2/sites-available/firstname.site.conf`:

```apache
<VirtualHost *:80>
    ServerName firstname.site
    ServerAlias www.firstname.site
    DocumentRoot /var/www/html/drupal
    <Directory /var/www/html/drupal>
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
```

```bash
sudo a2ensite firstname.site.conf
sudo systemctl reload apache2
```

> 📸 **Screenshot 23** — `firstname.site` enabled, Apache reloaded
> `[ Insert your screenshot here ]`

---

### 6.3 Drupal installation

Open `http://firstname.site` in the browser and follow the Drupal installation wizard.

> 📸 **Screenshot 24** — Drupal installation page in the browser
> `[ Insert your screenshot here ]`

> 📸 **Screenshot 25** — Drupal installed, site home page accessible
> `[ Insert your screenshot here ]`

---

## Final Verification

### Services summary

| Service | Package       | Port | Role                             |
|---------|---------------|------|----------------------------------|
| DNS     | bind9         | 53   | Domain name resolution           |
| Web     | apache2       | 80   | WordPress / Drupal hosting       |
| DB      | mysql-server  | 3306 | Database                         |
| PHP     | php           | —    | Server-side processing           |
| FTP     | vsftpd        | 21   | File transfer                    |

### Final test of all services

```bash
sudo systemctl status bind9 apache2 mysql vsftpd
curl http://name.blog
curl http://firstname.site
```

> 📸 **Screenshot 26** — All services active (bind9, apache2, mysql, vsftpd)
> `[ Insert your screenshot here ]`

> 📸 **Screenshot 27** — `name.blog` accessible in the browser (WordPress)
> `[ Insert your screenshot here ]`

> 📸 **Screenshot 28** — `firstname.site` accessible in the browser (Drupal)
> `[ Insert your screenshot here ]`

---

## Conclusion

This project enabled the deployment of a complete network and web hosting infrastructure on Linux. The skills acquired include:

**Network infrastructure (Part 0):**
- Machine identification with `hostnamectl`
- Modern network configuration with `systemd-networkd`
- Inter-VLAN routing and NAT with `nftables`

**Web services (Part 1):**
- DNS server configuration with BIND9 (forward and reverse zones)
- Installation and configuration of the LAMP stack (Apache, MySQL, PHP)
- Deployment of WordPress and Drupal sites with Apache Virtual Hosts
- FTP service configuration with vsftpd for file transfer
- Use of FileZilla from Windows to interact with the Linux server

> ⚠️ All screenshots (Proofs #1 to 5 + Screenshots 1 to 28) must be inserted at the designated locations before submitting the report.
