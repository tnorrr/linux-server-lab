# Lynis Findings — Full Reference

This is the itemized version of what's summarized in [HARDENING.md](../HARDENING.md#lynis-security-benchmarking). Two full audit rounds, addressing 30+ individual findings.

## Addressed

| Control ID | Finding | Fix |
|---|---|---|
| SSH-7408 | SSH hardening (8 settings) | See `security/ssh/sshd_config.snippet` |
| DEB-0880 | fail2ban config could be overwritten by updates | Copied `jail.conf` to `jail.local` |
| AUTH-9229 | PAM password hashing rounds | `SHA_CRYPT_MIN_ROUNDS` in `/etc/login.defs` |
| AUTH-9262 | No password strength enforcement | Installed `libpam-passwdqc` |
| AUTH-9282 | No account expiration set | `chage -M 90 -m 7 -W 14` |
| AUTH-9286 | Min/max password age not set | `PASS_MAX_DAYS`, `PASS_MIN_DAYS` in `/etc/login.defs` |
| AUTH-9328 | Default umask too loose | `UMASK 027` in `/etc/login.defs` |
| BANN-7126 / BANN-7130 | No legal login banner | `/etc/issue`, `/etc/issue.net`, plus `Banner` directive in sshd_config |
| BOOT-5122 | No GRUB bootloader password | Implemented, then reverted — see incident writeup in HARDENING.md |
| PKGS-7346 | Orphaned package configs | `apt autoremove --purge` (one exception kept, see below) |
| PKGS-7370 | No package verification tool | Installed `debsums` |
| PKGS-7394 | No patch management visibility | Installed `apt-show-versions` |
| DEB-0811 | No pre-upgrade changelog review | Installed `apt-listchanges` |
| DEB-0280 | PAM sessions not using isolated temp dirs | Installed `libpam-tmpdir` |
| NETW-3200 (x4) | Unused network protocols enabled | Blacklisted `dccp`, `sctp`, `rds`, `tipc` |
| ACCT-9622 | No process accounting | Installed `acct` |
| ACCT-9626 | No sysstat accounting | Installed `sysstat` |
| ACCT-9628 / ACCT-9630 | auditd installed with no rules | Real watch rules added, see `security/audit/audit.rules` |
| FINT-4350 | No file integrity monitoring | Installed AIDE |
| FINT-4402 | AIDE not using strong checksums | Added `+sha256` to `Full`/`VarFile` group definitions |
| HRDN-7222 | Compiler access not restricted | Checked — no compiler present, not applicable |
| HRDN-7230 | No malware scanner | Installed `rkhunter` |
| KRNL-6000 | sysctl values not hardened | See `security/sysctl/99-hardening.conf` |
| BOOT-5264 | Service hardening not reviewed | `systemd-analyze security` review; nginx/fail2ban sandboxed, ssh deliberately left alone |
| LOGG-2190 | Deleted-but-open files not checked | One-time `lsof +L1` check |

## Deliberately Skipped (with reasoning)

| Control ID | Finding | Why Skipped |
|---|---|---|
| FILE-6310 (x2) | /home, /var not on separate partitions | Would require repartitioning post-install; not worth redoing |
| USB-1000 | USB storage not disabled | Kept enabled for maintenance access |
| NAME-4028 | DNS domain checks | Not applicable — LAN-only, no registered domain |
| LOGG-2154 | No external logging host | No second machine yet; planned for a future project |
| HTTP-6710 | No HTTPS on base Nginx | Not meaningful without a real exposed domain |
| FILE-7524 | Generic file permission restrictions | Too vague to act on safely without itemized detail |
| TOOL-5002 | No automation tooling present | Not relevant at single-server scale |
| DEB-0810 | `apt-listbugs` not installed | Unavailable in this release's repositories even after enabling `universe`; substituted other patch-management tools instead |
| PKGS-7346 (partial) | One orphaned package (`grub-pc`) | Left in place due to its relation to the active boot configuration |
