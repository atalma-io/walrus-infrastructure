#!/bin/bash
set -ex

# Prefer non-interactive mode for this session
export DEBIAN_FRONTEND=noninteractive
  
# Variables for this cloud-init run
export IPV4_INGRESS_PORTS="9185"
export IPV6_INGRESS_PORTS=""
export SSH_PORT=22
export SWAP_COUNT=512 # 64GB swap file
export AUDIT_RULES_PATH="https://gist.githubusercontent.com/aaronmboyd/715b7edd2094a5919a6d1a6de7e2044d/raw/61b72fd4bc5a5e27e429bf8818e2e871954cc216/audit.rules"
export RELOAD_SYSCTL_PATH="https://gist.githubusercontent.com/aaronmboyd/ab7324dead486136bd10e95537776274/raw/0f3951ad61bd4bd0ff093b8053578139f9202f97/reload_sysctl_conf_on_boot.service"
export BANNER_PATH="https://gist.githubusercontent.com/aaronmboyd/b0e225aa326f4be003496d4f3581bfcf/raw/20f3fd646d0002e188d9021de13eca415a46f6d3/walrus-issue.txt"

# Change NEEDSRESTART behaviour in Ubuntu 24.04
# to automatically restart services that require it
# after package updates
# See: https://askubuntu.com/questions/1367139/apt-get-upgrade-auto-restart-services
echo "$nrconf{restart} = 'a';" > /etc/needrestart/no-prompt.conf

# Distribution upgrade with GRUB handling
apt-get update -y

# Configure GRUB to not install to any device during updates
echo "grub-pc grub-pc/install_devices_empty boolean true" | debconf-set-selections
echo "grub-pc grub-pc/install_devices string" | debconf-set-selections

# Perform upgrades with modified options
DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade
DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" dist-upgrade

# Install extra dependencies
apt-get install pkg-config build-essential libssl-dev curl jq -y

# Don't allow unattended-upgrades to reboot on it's own (uncomment the line)
sed -i -e "s/\/\/Unattended-Upgrade::Automatic-Reboot "false";/Unattended-Upgrade::Automatic-Reboot "false";/g" /etc/apt/apt.conf.d/50unattended-upgrades

# 1A SSH hardening
sed -i -e "s/#LogLevel INFO/LogLevel VERBOSE/g" /etc/ssh/sshd_config
sed -i -e "s/#AllowTcpForwarding yes/AllowTcpForwarding no/g" /etc/ssh/sshd_config
sed -i -e "s/#ClientAliveCountMax 3/ClientAliveCountMax 2/g" /etc/ssh/sshd_config
sed -i -e "s/#Compression delayed/Compression no/g" /etc/ssh/sshd_config
sed -i -e "s/#MaxAuthTries 6/MaxAuthTries 3/g" /etc/ssh/sshd_config
sed -i -e "s/#MaxSessions 10/MaxSessions 2/g" /etc/ssh/sshd_config
sed -i -e "s/#TCPKeepAlive yes/TCPKeepAlive no/g" /etc/ssh/sshd_config
sed -i -e "s/X11Forwarding yes/X11Forwarding no/g" /etc/ssh/sshd_config
sed -i -e "s/#AllowAgentForwarding yes/AllowAgentForwarding no/g" /etc/ssh/sshd_config
sed -i -e "s/#Port 22/Port $SSH_PORT/g" /etc/ssh/sshd_config
sed -i -e "s/#PasswordAuthentication yes/PasswordAuthentication no/g" /etc/ssh/sshd_config

# 1B Update SSH login banner
rm /etc/issue
curl $BANNER_PATH > /etc/issue
rm /etc/issue.net
cp /etc/issue /etc/issue.net
sed -i -e "s/#Banner none/Banner \/etc\/issue/g" /etc/ssh/sshd_config

# 1D Restart ssh
sudo systemctl restart ssh

# 2A Additional security packages
apt install fail2ban -y 
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
apt install rkhunter -y
apt install chkrootkit -y
apt install debsums -y
apt install usbguard -y
apt install ansible -y
apt install libpam-passwdqc -y

# 2B Clam AV
apt install clamav clamav-daemon -y
systemctl stop clamav-freshclam
systemctl enable clamav-freshclam --now

# 2C User and process accounting configuration
# Process accounting
apt install acct -y
touch /var/log/pacct # make a log file for process accounting
accton /var/log/pacct # enable process accounting on

# 2D Sysstat realtime performance monitoring
apt install sysstat -y
sed -i -e "s/ENABLED="false"/ENABLED="true"/g" /etc/default/sysstat
systemctl restart sysstat

# 2E Ubuntu audit daemon
# Ruleset from: https://github.com/Neo23x0/auditd/blob/master/audit.rules
apt install auditd audispd-plugins -y
auditctl -a exit,always -F path=/etc/passwd -F perm=wa
rm /etc/audit/rules.d/audit.rules
curl $AUDIT_RULES_PATH > /etc/audit/rules.d/audit.rules
systemctl restart auditd
  
# 2F Lynis
curl -fsSL https://packages.cisofy.com/keys/cisofy-software-public.key | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/cisofy-software-public.gpg
apt install apt-transport-https -y
echo 'Acquire::Languages "none";' | tee /etc/apt/apt.conf.d/99disable-translations
echo "deb https://packages.cisofy.com/community/lynis/deb/ stable main" | tee /etc/apt/sources.list.d/cisofy-lynis.list
apt update && apt install lynis
lynis show version

# 2G Docker
apt-get install ca-certificates -y
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc  
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
sleep 10
systemctl restart docker.socket
sleep 10
docker run hello-world

# 3A Tight home directory permissions
chmod 750 /home/ubuntu

# 3B Mail adjustment
postconf -e disable_vrfy_command=yes

# 3C Remove postfix banner information leak
sed -i -e "s/smtpd_banner/#smtpd_banner/g" /etc/postfix/main.cf
echo "smtpd_banner = \$myhostname" >> /etc/postfix/main.cf
service postfix restart
echo "* soft core 0" >> /etc/security/limits.conf
echo "* hard core 0" >> /etc/security/limits.conf

# 3D File permissions for root only
chmod 0600 /etc/crontab
chmod 0700 /etc/cron.d/
chmod 0700 /etc/cron.daily/
chmod 0700 /etc/cron.hourly/
chmod 0700 /etc/cron.monthly/
chmod 0700 /etc/cron.weekly/
chmod 0600 /etc/ssh/sshd_config
chmod 0600 /boot/grub/grub.cfg

# 3F Only allow root to rwx, and group r on compilers
chmod 0740 /usr/bin/as
chmod 0740 /usr/bin/cc
chmod 0740 /usr/bin/g++
chmod 0740 /usr/bin/gcc

# 3G login.defs settings
# First comment out these values
sed -i -e "s/PASS_MAX_DAYS/#PASS_MAX_DAYS/g" /etc/login.defs
sed -i -e "s/PASS_MIN_DAYS/#PASS_MIN_DAYS/g" /etc/login.defs
sed -i -e "s/UMASK/#UMASK/g" /etc/login.defs

# Then reinsert - only doing it this way because tabs do not play well with sed
echo "PASS_MAX_DAYS 90" >> /etc/login.defs
echo "PASS_MIN_DAYS 1" >> /etc/login.defs
echo "UMASK 027" >> /etc/login.defs

# 3H Umash to /etc/profile
echo "umask 027" >> /etc/profile

# 3I Disable USB storage
echo "blacklist usb-storage" | sudo tee -a /etc/modprobe.d/blacklist.conf

# 3J Disable blacklisted modules
modprobe --showconfig | egrep "^(blacklist|install)" | while read -r line ; do
    module=$(echo "$line" | awk -F' ' '{print $2}')
    echo "install $module /bin/true" >> /etc/modprobe.d/blacklist.conf
done;

# 3K Other kernel hardening
SYSCTL=/etc/sysctl.conf
sed -i -e "s/#kernel.sysrq=1/kernel.sysrq=0/g" $SYSCTL
sed -i -e "s/#net.ipv4.conf.all.forwarding=1/net.ipv4.conf.all.forwarding=1/g" $SYSCTL
sed -i -e "s/#net.ipv4.conf.all.send_redirects = 0/net.ipv4.conf.all.send_redirects=0/g" $SYSCTL
sed -i -e "s/#net.ipv4.conf.all.accept_redirects = 0/net.ipv4.conf.all.accept_redirects=0/g" $SYSCTL
sed -i -e "s/#net.ipv6.conf.all.accept_redirects = 0/net.ipv6.conf.all.accept_redirects=0/g" $SYSCTL
echo " " >> $SYSCTL
echo "fs.suid_dumpable=0" >> $SYSCTL
echo "kernel.perf_event_paranoid=3" >> $SYSCTL
echo "dev.tty.ldisc_autoload=0" >> $SYSCTL
echo "fs.protected_fifos=2" >> $SYSCTL

# 3L 10-network-security.conf
NETWORK=/etc/sysctl.d/10-network-security.conf
echo "net.core.bpf_jit_harden=2" >> $NETWORK
echo "net.ipv4.conf.all.log_martians=1" >> $NETWORK
echo "net.ipv4.conf.default.accept_redirects=0" >> $NETWORK
echo "net.ipv4.conf.default.accept_source_route=0" >> $NETWORK
echo "net.ipv4.conf.default.log_martians=1" >> $NETWORK
echo "net.ipv6.conf.default.accept_redirects=0" >> $NETWORK
echo "net.ipv4.conf.all.rp_filter=1" >> $NETWORK

# 3M 10-kernel-hardening.conf
KERNEL=/etc/sysctl.d/10-kernel-hardening.conf
sed -i -e "s/kernel.kptr_restrict/#kernel.kptr_restrict/g" $KERNEL
echo "kernel.core_uses_pid=1" >> $KERNEL
echo "kernel.dmesg_restrict=1" >> $KERNEL
echo "kernel.kptr_restrict=2" >> $KERNEL
echo "kernel.unprivileged_bpf_disabled=1" >> $KERNEL

# 3N 10-magic-sysrq.conf
MAGIC_SYSRQ=/etc/sysctl.d/10-magic-sysrq.conf
sed -i -e "s/kernel.sysrq/#kernel.sysrq/g" $MAGIC_SYSRQ
echo "kernel.sysrq=0" >> $MAGIC_SYSRQ

# 3O Reload config
service procps force-reload
sysctl -p

# 3P Make sure sysctl reloads some un-sticky options on boot
curl $RELOAD_SYSCTL_PATH > /etc/systemd/system/reload_sysctl_conf_on_boot.service
systemctl enable reload_sysctl_conf_on_boot.service

# 3Q Add hostname to /etc/hosts alias
export HOSTNAME=$(cat /etc/hostname)
sed -i -e "s/127.0.0.1 localhost/127.0.0.1 localhost $HOSTNAME/g" /etc/hosts

# 5A Create swap file
sudo dd if=/dev/zero of=/swapfile bs=128M count=$SWAP_COUNT

# 5B Update the read and write permissions for the swap file:
sudo chmod 600 /swapfile

# 5C Set up a Linux swap area:
sudo mkswap /swapfile

# 5D Make the swap file available for immediate use by adding the swap file to swap space:
sudo swapon /swapfile

# 5E Verify that the procedure was successful:
sudo swapon -s

# 5F Enable the swap file at boot time by editing the /etc/fstab file.
echo "/swapfile swap swap defaults 0 0" >> /etc/fstab

# 6A IPv4 firewall settings
# Flush all current rules from iptables
iptables -F

# Iterate IPV4 ingress ports and open
# First do SSH_PORT separately
iptables -A INPUT -p tcp --dport $SSH_PORT -j ACCEPT

for PORT in $IPV4_INGRESS_PORTS
do
    iptables -A INPUT -p tcp --dport $PORT -j ACCEPT
done

# Set default policies for INPUT, FORWARD and OUTPUT chains
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Set access for localhost
iptables -A INPUT -i lo -j ACCEPT

# Accept packets belonging to established and related connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Log dropped packets for debugging (limit to 5 logs per minute)
# iptables -A INPUT -m limit --limit 5/min -j LOG --log-prefix "iptables dropped: " --log-level 4

# Save settings so that iptables-persistent can reuse them on restart
mkdir /etc/iptables
touch /etc/iptables/rules.v4
iptables-save > /etc/iptables/rules.v4

# List iptables
iptables -L -v

# 6B ip6tables configuration script
# Flush all current rules from ip6tables
ip6tables -F

# Iterate IPV6 ingress ports and open
for PORT in $IPV6_INGRESS_PORTS
do
    ip6tables -A INPUT -p tcp --dport $PORT -j ACCEPT
done

# Set default policies for INPUT, FORWARD and OUTPUT chains
ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT ACCEPT

# Set access for localhost
ip6tables -A INPUT -i lo -j ACCEPT

# Accept packets belonging to established and related connections
ip6tables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Log dropped packets for debugging (limit to 5 logs per minute)
# ip6tables -A INPUT -m limit --limit 5/min -j LOG --log-prefix "ip6tables dropped: " --log-level 4

# Save settings so that ip6tables-persistent can reuse them on restart
iptables-save > /etc/iptables/rules.v6

# List rules
ip6tables -L -v

# 6C Install iptables-persistent
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
apt install -y iptables-persistent

# 7A Clean up apt
apt -y autoclean
apt -y autoremove
apt -y purge

# 7B Run Lynis audit
lynis audit system
clamscan -r /home/
