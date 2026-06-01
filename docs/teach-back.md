# Project 1 Teach-back — Linux Server Administration

these are my notes for talking about project 1 in interviews. wrote them so i wouldnt freeze when someone asks. each section is a question i might get and my answer in my own words.

## "Can you walk me through this Linux server project?"

i built an ubuntu 24.04 server on aws lightsail and hardened it. ssh key auth only, root login off, password auth off, cloud firewall locked to my home ip, fail2ban for brute force. i wrote a daily backup script that tars /etc, /home/ubuntu, and /var/log/nginx into a dated folder under /var/backups/server and prunes anything older than 7 days. it runs through a systemd timer. about 3 days into the project i noticed unfamiliar ssh sessions on the box, traced it back to a credential i had leaked, and rebuilt the whole thing from scratch. that incident ended up teaching me more than any of the tutorial bits.

## "What is the Linux filesystem layout?"

linux follows the filesystem hierarchy standard, which is the reason i can walk onto any linux box and know roughly where things are. /etc has system wide config — sshd, nginx, fail2ban all live there. /var/log is logs — auth.log for ssh, syslog for general system messages, /var/log/nginx for nginx. /home/ubuntu is the user space. /usr/local/bin is for binaries i install myself outside the package manager. /tmp is scratch and clears on reboot. without the FHS standard, linux skills wouldnt port across distros.

## "Explain Linux permissions to me."

three buckets, owner group others. three actions per bucket, read write execute. numerically r=4 w=2 x=1, sum them per bucket. so chmod 750 means owner rwx (7), group r-x (5), others nothing. for directories the execute bit is different, its the right to enter the directory, not to "run" it. without x on a directory i cant get inside even if i can read the listing. chmod 777 i avoid because it gives every account on the box full control over the file. when im not sure who needs access the answer is to figure that out, not to flatten it.

## "What is systemd and how do you manage services with it?"

systemd is the init system on every modern linux distro. its PID 1 and starts everything else. every service, timer, socket, mount is a "unit". my units go in /etc/systemd/system. the five commands i use are start, stop, restart, enable, disable. start and stop change live state right now. enable and disable change whether the unit comes up at boot. so i can have a unit thats started but not enabled (running now, gone after reboot) or enabled but not started (will come up next boot, not running now). for my backup i wrote a Type=oneshot service that runs the script and exits, paired with a .timer that triggers it daily. basically cron but with structured journal logs, automatic catch up via Persistent=true after a reboot, and the script exit code visible in systemctl status.

## "How do you read logs on a Linux server?"

two systems. the older one is flat files in /var/log — auth.log for ssh, syslog for general messages, /var/log/nginx for nginx. the newer one is the systemd journal via journalctl. the journal is structured, every entry has metadata about who wrote it, when, and at what priority. so i can do narrow queries like journalctl -u backup.service --since "1 hour ago" -p err and get only errors from one unit in a time window. for a box i havent seen before i start with journalctl -xe to see recent errors with explanations and narrow from there. sshd writes to both places so fail2ban can read auth.log while i can query the journal structurally.

## "Walk me through the security on this server."

7 overlapping layers. the principle is defense in depth, no single failure should be enough to compromise the box. one, the lightsail cloud firewall only lets ssh in from my home ip so the port isnt reachable from the rest of the internet. two, sshd accepts key auth only, passwords are disabled. three, root login disabled, so even if someone gets the ubuntu key they cant be root without sudo. four, MaxAuthTries 3 and LoginGraceTime 30 tighten the ssh negotiation window. five, fail2ban watches /var/log/auth.log and bans ips after repeated failures. six, unattended-upgrades installs security patches daily. seven, journalctl captures everything so after an incident i can reconstruct what happened. peel any single layer off and the others still hold.

## "Tell me about a time something broke on this project."

3 days in i was doing my normal check, ran ss -tn to look at tcp connections, and saw sessions from ips i didnt recognize. who showed ubuntu logged in from those ips. last -i confirmed it wasnt a one off, the access had been going on for hours.

the cause was on me. earlier that week i had pasted the contents of the .pem file into an ai assistant while debugging a connection issue. i treated it as text. its a credential. the moment it leaves my machine its not mine anymore.

i had to decide what to do. first thought was kill the sessions and rotate the key. but once someone has had access for hours i dont actually know what got changed. there is no command that proves a linux box is clean after that. i deleted the instance, generated a new ed25519 key locally that hasnt left my machine since, and rebuilt with the hardening from day one instead of as an afterthought.

the part that stuck with me is i caught it at all. i wasnt running ss as a security tool. it was just the command i used to check my own session was up. and the same output that confirms my session also shows everyone elses session. the basic commands i learned for normal ops are the same ones that catch when something is off.

what i tell myself now: credentials dont go into chat tools, full stop. and learning the normal commands well is what makes detection possible in the first place.

## "Tell me about your backup script."

it tars /etc, /home/ubuntu, and /var/log/nginx into a dated folder under /var/backups/server/YYYY-MM-DD/, one tar.gz per source so i can pull just one source from a day if i need to. runs through a systemd timer with OnCalendar=daily and RandomizedDelaySec=15m so the start jitters within a 15 minute window. on one host that doesnt matter, but if i scale it to a fleet itd matter. three engineering choices i can defend. set -euo pipefail at the top so any error, undefined variable, or pipe failure stops the script instead of producing a half complete archive. defensive check that each source exists before adding it to tar, so if a directory i expected got removed the script logs a warning and keeps going. running through a systemd timer not cron, so i get structured journal logs and the script exit code shows up in systemctl status. it also tees output to /var/log/backup.log because i wanted a flat file copy in case the journal rotates.

## "What would you do differently if this were production?"

a few things. backups would go off the box. right now they sit on the same disk as the server which is dumb if the disk dies. real version would be aws s3 sync or scp to another machine. infrastructure would be in code. right now if the box dies i rebuild by clicking in the lightsail console. real prod has the whole thing in terraform and ansible so i can reproduce it from git in minutes. monitoring instead of just passive logs. right now i go look at journalctl when i want to know whats happening. real prod has prometheus or cloudwatch with alerts to a pager. centralized log shipping instead of per host. and real tls with a real domain instead of plain http.
