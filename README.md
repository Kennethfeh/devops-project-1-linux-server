# devops-project-1-linux-server

ubuntu 24.04 box on aws lightsail. hardened it, set up daily backups, ran into a real ssh incident in the middle. project 1 of my devops bootcamp.

## What I built

a single lightsail instance on the $5/month tier running ubuntu 24.04. nginx serving the default page on port 80. ssh on 22 locked behind the cloud firewall to my home ip. a backup script that runs through a systemd timer once a day, tars /etc, /home/ubuntu, and /var/log/nginx into a dated folder under /var/backups/server, keeps 7 days, prunes the rest. fail2ban watches the sshd auth log. journalctl is where i go when i want to know what happened on the box.

nothing flashy. its the first server in my bootcamp and i wanted to get the basics solid before moving up the stack.

## Architecture

one lightsail box, single AZ, no load balancer. the cloud firewall only lets port 22 in from my home ip. port 80 is open since nginx is just serving the default page.

inside the box: nginx, sshd, fail2ban, unattended-upgrades. backup.timer fires backup.service once a day with a 15 minute random delay. the service runs /home/ubuntu/scripts/backup.sh as root because it needs to read /etc and write to /var/backups. output goes to journalctl and also gets teed into /var/log/backup.log so i have both copies.

state and backups live on the same disk. not what i would do for real prod but its fine for a learning box.

## Skills demonstrated

- provisioning ubuntu on a cloud (lightsail) with ssh key auth
- knowing the filesystem layout: /etc, /var/log, /home, /usr/local/bin
- chmod and chown including the directory execute bit
- apt install/upgrade, dpkg -L to find where packages put their files
- writing systemd .service and .timer units, knowing the difference between start and enable
- reading logs with journalctl: -u, --since, -p err
- ssh hardening in sshd_config: PermitRootLogin no, PasswordAuthentication no, MaxAuthTries, LoginGraceTime
- fail2ban with the sshd jail
- bash with set -euo pipefail and defensive checks before destructive ops
- responding to a real ssh incident, including deciding to rebuild instead of clean

## How it was built

started with a fresh lightsail instance. generated an ed25519 keypair on my mac with ssh-keygen and dropped the public key into the instance setup. first ssh in worked first try.

walked around the filesystem manually for the first hour. opened /etc, /var/log, /home/ubuntu and read what was there. put my backup script under /home/ubuntu/scripts and chmod 750 so only me can change or run it.

installed nginx, fail2ban, unattended-upgrades. used dpkg -L when i wanted to see exactly where packages put things.

systemd was the part i had to slow down for. wrote backup.service as Type=oneshot pointing at the script, with StandardOutput=journal and StandardError=journal. wrote backup.timer with OnCalendar=daily, Persistent=true, RandomizedDelaySec=15m. Persistent=true catches up runs that were missed if the machine was off. enabled it with systemctl enable --now backup.timer.

logs i mostly read through journalctl. journalctl -u backup.service --since "1 day ago" became my default daily check. for errors i use -p err.

networking i checked with ss -tlnp to confirm only sshd and nginx were listening. closed the lightsail firewall for port 22 down to my home ip.

ssh hardening: edits to /etc/ssh/sshd_config, root login off, password auth off, MaxAuthTries 3, LoginGraceTime 30, then systemctl reload sshd. fail2ban i mostly left on defaults with the sshd jail, bantime 1h, findtime 10m, maxretry 5.

backup script: set -euo pipefail. defensive check that each source exists before tarring. per source archives inside the dated folder so i can pull just one source from one day without unpacking the whole thing. find -mtime +7 -delete for retention. logs go to the journal because the service sends them there and also teed to /var/log/backup.log.

## What broke and how I fixed it

the big one was the ssh incident. about 3 days into the project i was doing my normal check, ran ss -tn and saw active sessions from ips i didnt know. who confirmed they were logged in as ubuntu. last -i showed they had been coming in for hours.

cause was on me. earlier that week i had pasted the contents of the .pem file to an ai while debugging a connection issue. i treated it like a config file. it was a credential. the second it leaves my machine its not mine anymore.

first thought was kill the sessions and rotate the key. didnt go with that. once someone has had access for an unknown amount of time i dont actually know what got changed. there is no command that proves a linux box is clean after that. i deleted the instance, generated a new ed25519 key locally that hasnt left my machine since, and rebuilt with the hardening from day one instead of as an afterthought.

the part that stayed with me wasnt really the security side. its that i caught it because i had been using ss and who and last for normal stuff. just checking my own session. those same commands also show every other session. so the tools i was learning for basic ops are the same tools that flag when something is off. that changed how i look at any new command now.

the smaller one was nginx. edited /etc/nginx/sites-available/default and broke a line. ran systemctl reload nginx and it didnt error. except systemctl status nginx showed the reload had actually failed and the old process kept serving the old config. now i run nginx -t before any reload. saved me from doing the same thing later in front of someone who would have seen it first.

## Trade-offs and what I'd do differently

- lightsail vs ec2. lightsail was right for a $5 learning box. for real work i would use ec2 because of networking flexibility.
- backups go to the same disk. if the disk dies they die too. real version would write to s3 or another machine. the script is shaped so swapping the tar block for aws s3 sync would be a small change.
- no tls yet. nginx is plain http on purpose. tls goes in project 2 with a real domain and lets encrypt.
- no terraform yet. provisioned in the console. project 3 redoes this in terraform so the whole box is reproducible from git.
- single host fail2ban. fine for one box. at scale i would ship logs centrally and ban at the edge instead of per host.

## What's in this repo

- scripts/backup.sh — the daily backup script
- configs/backup.service — systemd service unit
- configs/backup.timer — systemd timer (daily, with the 15 min jitter)
- docs/teach-back.md — my notes on every concept the bootcamp covered so i can talk about this in interviews without freezing

## References

- [Filesystem Hierarchy Standard](https://refspecs.linuxfoundation.org/FHS_3.0/fhs/index.html)
- [systemd.timer](https://www.freedesktop.org/software/systemd/man/systemd.timer.html)
- [fail2ban manual](https://www.fail2ban.org/wiki/index.php/Main_Page)
- [Ubuntu OpenSSH docs](https://ubuntu.com/server/docs/openssh-server)
