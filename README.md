# devops-project-1-linux-server

A hardened Ubuntu 24.04 server on AWS Lightsail, with automated daily backups, SSH lockdown, fail2ban, and a real SSH incident in the middle that taught me defense in depth from the inside out.

## What I built

A single Lightsail Ubuntu 24.04 instance, locked down to my home IP, serving an Nginx default page over HTTP. SSH key auth only — no passwords, no root login. A systemd `.timer` runs a backup script daily that tars `/etc`, `/home/ubuntu`, and `/var/log/nginx` into a date-stamped directory under `/var/backups/server/`, with a 7-day retention sweep. fail2ban watches `/var/log/auth.log` for brute-force attempts. journalctl is the source of truth for everything else. First server in my DevOps bootcamp — foundation for everything that comes after.

## Architecture

One Lightsail Ubuntu 24.04 box on the $5/month tier. Cloud firewall locked to my home IP for SSH (port 22); port 80 open for Nginx. Nginx serves the default site. A `backup.timer` unit triggers `backup.service` once a day with up to 15 minutes of randomized delay; the service runs `/home/ubuntu/scripts/backup.sh` as root, which produces a `/var/backups/server/YYYY-MM-DD/` directory containing one `.tar.gz` per source. fail2ban watches sshd auth attempts. Logs go to both `/var/log/backup.log` and the systemd journal so I can query them either way.

## Skills demonstrated

- **Provisioning** an Ubuntu host on a cloud provider (AWS Lightsail) and configuring SSH key-based access from a fresh ed25519 keypair
- **Filesystem Hierarchy Standard** — actually knowing what lives in `/etc`, `/var/log`, `/home`, `/usr/local/bin`, and using that to navigate any Linux box without docs
- **Linux permissions** — numeric and symbolic chmod, group ownership, the directory-execute bit, and why `chmod 777` is almost never the answer
- **Package management** with apt — install, upgrade, dpkg query for "which package put this file here"
- **systemd** — writing `.service` and `.timer` units, the difference between `start`/`stop` (right now) and `enable`/`disable` (at boot), `Type=oneshot` for batch jobs
- **Log reading** — `journalctl -u <unit> --since "1 hour ago" -p err` for narrowing in, plus the traditional `/var/log/*.log` files
- **SSH hardening** — key-only auth, root login off, password auth off, `MaxAuthTries`, `LoginGraceTime`
- **Brute-force defense** with fail2ban (sshd jail, `bantime`, `findtime`, `maxretry`)
- **Cloud + host firewalls** working together as defense in depth, not as substitutes for each other
- **Bash scripting that fails safely** — `set -euo pipefail`, defensive guards on missing sources, structured logging
- **Incident response** — detecting unfamiliar sessions with `ss -tn` / `who` / `last -i`, deciding when to rebuild instead of clean

## How it was built

**Provisioning.** Created the Lightsail instance from the console, generated an ed25519 keypair locally with `ssh-keygen`, pasted the public key during setup. First connection: `ssh -i ~/.ssh/bootcamp-v2 ubuntu@<ip>`.

**Filesystem and permissions.** Walked the FHS manually — actually went into `/etc`, `/var/log`, `/home/ubuntu` and read what was there. Created `/home/ubuntu/scripts/` for `backup.sh`, set it `0750` so only owner can modify and execute.

**Packages.** `apt update && apt upgrade -y`, then installed `nginx`, `fail2ban`, `unattended-upgrades`. Learned to use `dpkg -L <pkg>` to find out where things went.

**systemd.** Wrote `backup.service` as `Type=oneshot` running the script as root with `StandardOutput=journal` and `StandardError=journal`. Wrote `backup.timer` with `OnCalendar=daily Persistent=true RandomizedDelaySec=15m` — `Persistent=true` catches up missed runs after reboot, `RandomizedDelaySec` keeps every-machine-runs-at-the-same-second from becoming a problem if I ever scale this out. Enabled with `systemctl enable --now backup.timer`.

**Logs.** journalctl became my default. `journalctl -u backup.service --since "1 day ago"` to see backups. `journalctl -u sshd -p err` to filter for errors. The backup script also writes to `/var/log/backup.log` directly so I have a flat-file fallback if I ever lose the journal.

**Networking.** Reviewed open ports with `ss -tlnp` — only `sshd` and `nginx` were listening. Closed the Lightsail firewall for port 22 to my home IP only; left 80 open.

**SSH hardening.** Edited `/etc/ssh/sshd_config`: `PermitRootLogin no`, `PasswordAuthentication no`, `MaxAuthTries 3`, `LoginGraceTime 30`. `systemctl reload sshd`. Then `fail2ban-client` with the default sshd jail, `bantime = 1h`, `findtime = 10m`, `maxretry = 5`.

**The backup script.** `set -euo pipefail`. Defensive check that each source directory exists before adding it to `tar`. Per-day directory with one archive per source — makes it easy to extract just `/etc` from a specific day without untarring the whole thing. `find -mtime +7 -delete` for retention. All output goes to both the journal (via stdout from the unit) and `/var/log/backup.log`.

## What broke and how I fixed it

**The SSH incident.** A few days into the project I ran `ss -tn` and saw active sessions from IPs I didn't recognize. `who` confirmed they were logged in as `ubuntu`. `last -i` showed connections going back several hours. My first instinct was to kill the sessions and rotate the key. My second instinct, which I went with, was to assume the host was compromised and rebuild from scratch.

Root cause was on me. I had shared the `.pem` file with an AI assistant earlier that week while debugging a connection issue, treating the file as if it were a config snippet. It was a credential. The lesson — credentials don't go into chat tools, ever, full stop. The remediation: deleted the instance, generated a fresh ed25519 key locally that has never left my machine, and rebuilt with the SSH hardening from day one rather than retrofitting it.

The deeper lesson was operational. Detection happened because I'd already learned `ss` and `who` and `last` for verifying my own work. The exact same commands that confirm "yes, I'm connected" also reveal "and so are these other people." Defensive command-line literacy *is* detection.

**Nginx config typo.** Earlier on, I edited `/etc/nginx/sites-available/default` and broke a line. `systemctl reload nginx` exited 0 but the service had silently entered a failed state — the old process kept serving the old config. I caught it from `systemctl status nginx` showing the reload error. From then on I always run `nginx -t` before reloading. It's the difference between knowing something is broken and finding out after a user does.

## Trade-offs and what I'd do differently

- **Lightsail vs raw EC2.** Lightsail was right for a learning environment — flat $5/month, simple networking. For real production I'd use EC2: more flexible, but I'd be paying a complexity tax to get there.
- **On-host backups.** Backups currently land on the same disk as the server. If the disk dies, so do the backups. A real version writes to S3 or another machine. The script is structured so swapping the `tar` block for `aws s3 sync` would be a small change.
- **No TLS yet.** Nginx serves plain HTTP. That's deliberate — TLS belongs in Project 2 paired with a real domain and Let's Encrypt. Adding a self-signed cert here would teach me nothing the project doesn't already cover.
- **No infrastructure as code.** I provisioned via the Lightsail console because Project 1 is about Linux, not Terraform. If I had to rebuild the host tomorrow it'd be 20 minutes of clicking. In a later project I'll redo this kind of provisioning in Terraform so the box is reproducible from git.
- **Single-host fail2ban.** Works fine for one box. At scale you centralize log shipping into a SIEM and ban at the edge (firewall / WAF) instead of per-host.

## What's in this repo

- `scripts/backup.sh` — the daily backup script with 7-day retention
- `configs/backup.service` — systemd service unit (`Type=oneshot`, runs as root, output to journal)
- `configs/backup.timer` — systemd timer (`OnCalendar=daily`, `Persistent=true`, `RandomizedDelaySec=15m`)
- `docs/teach-back.md` — my full interview-prep teach-back covering every major concept in Project 1

## References

- [Filesystem Hierarchy Standard](https://refspecs.linuxfoundation.org/FHS_3.0/fhs/index.html)
- [systemd.timer documentation](https://www.freedesktop.org/software/systemd/man/systemd.timer.html)
- [fail2ban manual](https://www.fail2ban.org/wiki/index.php/Main_Page)
- [Ubuntu Server — OpenSSH](https://ubuntu.com/server/docs/openssh-server)
