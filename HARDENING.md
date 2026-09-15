# HARDENING.md — Home Lab Server Hardening & Expansion

**Author:** Tyler Norton
**Date:** 9/14/2026

## What This Is

A Linux server built from scratch on repurposed hardware (Lenovo Legion laptop, i7-11800H, 14GB RAM), progressing through three phases:

1. **Base hardening** — minimal Ubuntu Server install, SSH lockdown, firewall, intrusion prevention, file integrity monitoring, and audit logging
2. **Security benchmarking** — two rounds of Lynis-driven remediation covering 30+ individual findings
3. **Homelab expansion** — a Docker-based service platform (Portainer, Uptime Kuma, Vaultwarden, Jellyfin, Nginx Proxy Manager, Homepage) layered on top without weakening the original hardening

This document covers what I did, why I did it, what broke along the way, and what I deliberately left alone.

---

## Architecture

- **OS:** Ubuntu Server LTS (minimal/headless install, no GUI)
- **Access:** SSH only, key-based auth, non-default port
- **Reverse web tier:** original Nginx (port 80/443, from base hardening) plus Nginx Proxy Manager (port 8181/8443, for Docker services requiring HTTPS)
- **Container runtime:** Docker and Docker Compose
- **Services running:** Portainer (container management), Uptime Kuma (monitoring), Vaultwarden (password manager), Jellyfin (media server), Pi-hole (network-wide DNS filtering), Homepage (dashboard)
- **Monitoring/integrity:** AIDE (file integrity), auditd (audit logging), fail2ban (brute-force protection), Uptime Kuma (service uptime)

---

## Threat Model

This server is reachable only on the home LAN. Nothing is exposed to the public internet. The primary threats I considered:

- **Unauthorized SSH access** — mitigated via key-only auth, non-default port, fail2ban, and a deny-by-default firewall
- **Compromise via an exposed service** — each service is on its own explicitly allowlisted port; nothing runs with broader network exposure than it needs
- **Undetected file tampering** — mitigated via AIDE with SHA-256 checksums and auditd watch rules on sensitive files
- **Physical access to the machine** — partially addressed (see GRUB section below), and ultimately deprioritized in favor of remote availability
- **Weak/default credentials on self-hosted services** — each service (Portainer, NPM, Uptime Kuma, Vaultwarden) has its own distinct admin credentials, none left at defaults

---

## Base Hardening

### SSH
- Key-based authentication only; password authentication disabled
- Root login disabled
- Moved off the default port
- Additional `sshd_config` hardening applied in Lynis Round 1 (`AllowTcpForwarding no`, `X11Forwarding no`, `MaxAuthTries 3`, `MaxSessions 2`, `ClientAliveCountMax 2`, `TCPKeepAlive no`, `LogLevel VERBOSE`, `AllowAgentForwarding no`)

**Incident — SSH socket activation:** Changing `Port` in `sshd_config` had no effect on this Ubuntu release, because it uses `ssh.socket` (systemd socket activation) rather than the traditional model where `sshd` binds its own port directly. The actual fix required a systemd override (`systemctl edit ssh.socket`) clearing and re-setting `ListenStream`. None of the tutorials I initially followed mentioned this. I diagnosed it by checking `ss -tulpn` to confirm what was actually listening, versus what the config file claimed should be listening.

### Firewall (ufw)
- Default deny incoming, default allow outgoing
- Every service port explicitly allowlisted as it was added, so nothing was opened broadly
- ufw wasn't installed by default on this minimal image; I had to install it explicitly before any rules could be applied

### fail2ban
- Installed and enabled with the SSH jail active
- `jail.conf` copied to `jail.local` (Lynis Round 1) so future package updates won't silently overwrite local customization

### Nginx (original)
- Deployed as the "service to secure" for the base project
- Firewall restricted to only the ports Nginx actually uses (80/443)

### Logging
- `/var/log/auth.log` didn't exist by default on this Ubuntu version (journald-only logging out of the box). I installed `rsyslog` to restore the traditional log file, since fail2ban's default config expects it.

---

## Lynis Security Benchmarking

I ran two full audit rounds, addressing roughly 30+ individual findings. Full details below; skipped items are documented with reasoning rather than silently ignored.

### Round 1 highlights
- SSH hardening (8 settings, see above)
- fail2ban `jail.local` copy
- Password policy: `PASS_MAX_DAYS`, `PASS_MIN_DAYS`, `UMASK 027`, `SHA_CRYPT_MIN_ROUNDS` in `/etc/login.defs`
- `libpam-passwdqc` for password strength enforcement
- Login banners (`/etc/issue`, `/etc/issue.net`): required an additional `Banner /etc/issue.net` directive in `sshd_config` to actually display on SSH connect. Text alone in the files wasn't sufficient.
- GRUB bootloader password (see incident writeup below)
- Package cleanup (`apt autoremove --purge`): one orphaned config (`grub-pc`) was deliberately left in place due to its relation to the active boot configuration
- `libpam-tmpdir`, `rkhunter` (malware scanner), `AIDE` (file integrity monitoring), `auditd` (initially installed with no rules, addressed in Round 2), and a compiler access restriction check (no compiler present on this minimal image, so not applicable)

### Round 2 highlights
- APT safety tooling: `apt-listchanges`, `debsums`, `apt-show-versions`. `apt-listbugs` was unavailable in this release's repositories even after enabling `universe`, likely deprecated or removed from the archive, so I substituted the other three.
- Explicit password expiration via `chage` on the account (login.defs settings alone don't retroactively apply)
- Disabled unused network protocols (`dccp`, `sctp`, `rds`, `tipc`) via modprobe blacklist
- Real auditd rules added (`/etc/passwd`, `/etc/shadow`, `/etc/ssh/sshd_config`, `/var/log/auth.log`, watching for writes and attribute changes)
- **AIDE checksum gap:** Lynis flagged that AIDE wasn't using SHA-256/512. I traced this to Ubuntu's packaged config, which splits rules across `/etc/aide/aide.conf.d/`, and found that the group definitions (`Full`, `VarFile`) used throughout the ruleset had no hash algorithm specified at all. I added `+sha256` to both groups and rebuilt the baseline database.
- `acct` and `sysstat` for process/system accounting
- General sysctl network hardening (`accept_redirects=0`, `send_redirects=0`, `accept_source_route=0`, `icmp_echo_ignore_broadcasts=1`, `tcp_syncookies=1`, `randomize_va_space=2`)
- `systemd-analyze security` review of ssh/nginx/fail2ban services

### systemd service sandboxing
I applied `PrivateTmp=yes`, `ProtectHome=yes`, and `NoNewPrivileges=yes` to **nginx.service** and **fail2ban.service** via systemd overrides. Both improved from a 9.6 to 8.9 security score (lower is better) with no functional impact.

**Deliberately not applied to ssh.service.** SSH is the only remote access point into this server. Sandboxing restrictions that could break its ability to authenticate or spawn sessions carry a lockout risk that isn't justified by the marginal security gain, especially for a single-admin home server with no other access path if it broke.

### Skipped Lynis findings (with reasoning)
- **Separate partitions for /home, /var** — would require repartitioning the disk; not worth redoing post-install
- **Disable USB storage** — kept enabled for ongoing maintenance access (re-flashing installers, physical troubleshooting)
- **DNS domain name checks** — not applicable; this is a LAN-only box with no registered domain
- **External logging host** — no second machine available yet; a natural fit for the future Cloud Sentry project in my broader learning roadmap
- **HTTPS on the original Nginx instance** — not meaningful without a real exposed domain (later addressed for Vaultwarden specifically via Nginx Proxy Manager, where it actually mattered)
- **Generic file permission restrictions** — too vague to act on without Lynis's full itemized file list; not safe to apply blindly
- **Automation tooling (Ansible/Puppet) presence** — not relevant for a single-server home lab; will matter more once I reach the Terraform/CI-CD stage of my broader learning path

---

## Incident: GRUB Bootloader Password Lockout

**Goal:** Prevent unauthorized access to boot options and recovery mode by requiring a password at the GRUB menu (Lynis BOOT-5122).

**What happened:** A typo in the generated hash line (`password_pbkd2` instead of `password_pbkdf2`) caused GRUB to fail to parse the password directive at all. `superusers="admin"` was still set, meaning every boot demanded authentication, but with no valid password ever actually stored. After an unplanned power loss (the laptop's battery died), the server came back up fully locked at the GRUB prompt, with no password that could possibly work.

**Recovery process:**
1. Attempted TTY switching on the Ubuntu Server installer to reach a rescue shell. This failed because the laptop's hybrid graphics weren't rendering virtual terminal switches correctly.
2. Fell back to a full Ubuntu **Desktop** live USB instead, which provided a normal GUI terminal with no TTY switching required.
3. Identified the disk as LVM-based (`nvme0n1p1` EFI, `nvme0n1p2` /boot, `nvme0n1p3` LVM physical volume containing `ubuntu-vg/ubuntu-lv`).
4. Activated the volume group (`vgchange -ay`), mounted the logical volume plus `/boot` and `/boot/efi` separately, bind-mounted `/dev`, `/proc`, `/sys`, and chrooted in.
5. The first repair attempt fixed the missing letter but introduced a second typo (a stray literal word `PBKDF2` left in the line from a copy/paste), so it was still locked out.
6. On the second attempt, I removed the `superusers`/`password_pbkdf2` lines entirely rather than continuing to fight the syntax.
7. Regenerated GRUB (`update-grub`), exited the chroot, and rebooted (`systemctl reboot -i` was needed to bypass the live environment's own session inhibitor).

**Outcome:** GRUB password control was ultimately **removed rather than fixed**. For an unattended, remotely-managed server, requiring physical presence and a password at every single boot, including after a routine power blip, creates an availability risk that outweighs the security benefit of the control. This is especially true at this scale, where there's a single admin, the box is LAN-only, and physical access to the location is already reasonably trusted. This was a deliberate reversal of an earlier decision, made after direct experience with the failure mode.

**Skills demonstrated:** live-environment recovery, LVM disk layout under chroot, distinguishing a graphics/driver issue from an actual command failure while troubleshooting blind, and, maybe most importantly, recognizing when a security control isn't worth keeping for a given threat model, even after already implementing it once.

---

## Homelab Expansion

Once base hardening and Lynis remediation were complete, I expanded the server into a small self-hosted service platform. This section covers what I added and the non-obvious problems I ran into along the way.

### Docker
- Installed via the official convenience script
- **AIDE exclusion added first:** `/var/lib/docker` excluded from AIDE's watch rules before installing Docker, since container image layers and runtime state change constantly and would otherwise flood every future integrity check with false positives
- Baseline rebuilt after Docker install to establish a clean starting point

### Services deployed (all Docker containers, `--restart=unless-stopped`)
| Service | Purpose | Port |
|---|---|---|
| Portainer | Docker management UI | 9443 |
| Uptime Kuma | Service monitoring/alerting | 3001 |
| Vaultwarden | Self-hosted password manager | 8080 (internal), 8443 via reverse proxy |
| Jellyfin | Media server with Intel Quick Sync hardware transcoding | 8096 |
| Nginx Proxy Manager | Reverse proxy and HTTPS for internal services | 8181 (admin), 8443 (proxied HTTPS) |
| Pi-hole | Network-wide DNS ad/tracker filtering | 53 (DNS), 8090 (admin) |
| Homepage | Unified dashboard linking all of the above | 3000 |

Firewall rules were added incrementally, one port at a time, matching the same allowlist-only approach as the base hardening.

### Notable problems and fixes

**Vaultwarden HTTPS chain.** Bitwarden's web vault and mobile apps require HTTPS to function fully. Since there's no real public domain for this LAN-only box, I implemented HTTPS with:
- A self-signed certificate generated with `openssl` (`vault.home` as the CN)
- Uploaded to Nginx Proxy Manager as a Custom certificate (NPM doesn't auto-generate self-signed certs; that was an early wrong assumption on my part that needed correcting)
- An NPM Proxy Host forwarding `vault.home` → `[laptop-LAN-IP]:8080` (Vaultwarden's internal port), with the uploaded certificate attached and Force SSL enabled

Debugging this involved an incomplete NPM container recreation (missing the `8443:443` port mapping on first run, verified via `docker port`), and an SNI mismatch when testing with `curl` against `localhost` instead of the certificate's actual configured hostname (confirmed working once tested with `--resolve` against the correct domain). Final client-side access got resolved with a Windows hosts file entry on my PC and a direct-IP entry in the Bitwarden app's self-hosted server field on my phone, rather than relying on DNS that doesn't exist for a `.home` TLD.

**Uptime Kuma to Portainer false "down" status.** A TCP port check from Kuma kept reporting Portainer as down even though the port was confirmed open both externally and via direct `nc` testing from the host shell. The root cause: containers on a Docker bridge network don't always reliably reach the host's own external or LAN IP, due to how Docker's NAT and hairpin routing interact with the host. This is a common but non-obvious Docker networking limitation, distinct from a normal reachability problem. I fixed it by recreating the Uptime Kuma container with `--add-host=host.docker.internal:host-gateway` and pointing the monitor at `host.docker.internal` instead of the LAN IP.

**Homepage `HOMEPAGE_ALLOWED_HOSTS`.** Recent versions added mandatory host-header validation for security. Without explicitly allowlisting the host/IP being used to access it, Homepage returns a hard "Host validation failed" error rather than rendering. This required setting `HOMEPAGE_ALLOWED_HOSTS` as an environment variable and **fully recreating** the container, since a `restart` alone doesn't pick up new environment variables; only a full stop/remove/recreate does.

**Pi-hole port 53 conflict with systemd-resolved.** Ubuntu's `systemd-resolved` binds port 53 by default, which collides directly with Pi-hole's own DNS listener. Resolved by setting `DNSStubListener=no` in `/etc/systemd/resolved.conf` and re-pointing `/etc/resolv.conf` to systemd-resolved's real (non-stub) socket, so the host itself retained working DNS resolution after disabling the conflicting listener.

**Pi-hole "ignoring query from non-local network."** After pointing devices at Pi-hole for DNS, queries from the actual LAN were being silently dropped. Root cause: Pi-hole's Docker container, on the default bridge network, only treats the internal Docker network as "local," so real LAN traffic from outside the container's own subnet gets flagged as non-local and ignored, a known limitation of running Pi-hole under Docker's bridge networking rather than host networking. Resolved via Pi-hole's own **Settings → DNS → Interface Settings → Permit all origins**, rather than restructuring the container onto host networking, since the server is already firewalled to LAN-only access at the ufw level and the added exposure from this setting is minimal in that context.

**Pi-hole web UI unreachable despite DNS (port 53) working.** The container was healthy and resolving DNS queries correctly, but the admin dashboard on port 8090 was completely unreachable, with nothing listening on that port at all. The container had been recreated at some point without the `-p 8090:80` mapping intact, meaning the web UI port was simply never exposed even though the DNS ports were. Fixed by removing and recreating the container with the full port mapping explicitly included, confirmed afterward with `docker port pihole`.

---

## What I'd Do Differently at Scale

- **Centralized logging** — right now, each service's logs live wherever that service puts them. At real scale (or as a natural extension of the Cloud Sentry project later in my roadmap), I'd ship everything to a central log aggregator (ELK/Loki) rather than checking `docker logs` per container.
- **Config management** — every service here was deployed with a hand-typed `docker run` command. A production setup (or even this one, in hindsight) would benefit from Docker Compose files checked into version control, so the entire stack is reproducible from a single `git clone` and `docker compose up`, rather than a list of commands in a guide.
- **Secrets handling** — admin credentials for each service were set manually and are only as safe as my own memory and password manager discipline. At scale, these would live in a proper secrets manager rather than being set ad hoc per service.
- **Multi-host separation** — right now, everything (the hardened base server and the homelab services) lives on one machine. In a real environment, I'd separate these concerns onto different hosts so an incident in one service's container doesn't share a blast radius with the underlying hardened host.
- **Automated backups** — none of the service data (Vaultwarden vault, Jellyfin config, NPM certificates) is currently backed up anywhere beyond this single disk. A real deployment needs this from day one, not as an afterthought.

---

## Summary

I started from a wiped laptop and an Ubuntu Server ISO. I ended up with a hardened, benchmarked, monitored server running a real multi-service platform, after breaking and recovering the bootloader once, debugging Docker networking quirks, chasing down a chain of certificate and DNS issues, and making (and later reversing) real security tradeoff decisions along the way. If anything, the failures documented here are more representative of real system administration and security work than a clean, uninterrupted success would have been.
