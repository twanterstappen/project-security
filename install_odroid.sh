#!/usr/bin/bash
# Author: Twan Terstappen
# Purpose: Installing odroid as router/Access-Point/Firewall
# Created: 14-10-2023


# Setting echo colors
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;32m"
BLUE="\033[0;34m"
NOCOLOR="\033[0m"

echo -e "${RED}"
read -p "Do you want to install iptables and update your system? Host need a restart after updating and installing iptables (y/N): " CONT
echo -e "${NOCOLOR}"
if [ "$CONT" = "y" ] ; then
    echo -e "${YELLOW}Updating system!${NOCOLOR}"
    sleep 3
    #sudo apt --fix-broken install
    sudo apt update -y
    sudo apt upgrade -y
    sudo apt install iptables -y
    echo ""
    echo -e "${YELLOW}Rebooting system!${NOCOLOR}"
    sleep 3
    sudo reboot now
fi
## Install packages
# Basic packages
# sudo apt-get install dnsutils dos2unix -y
sudo apt-get install dhcpcd5 dnsmasq hostapd -y

# Adding odroid to host, otherwise you get error messages
sudo hostname router-wa
echo '127.0.0.1 router-wa' >> /etc/hosts

# Installing silently iptables-persistent for save iptables
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
sudo apt-get -y install iptables-persistent


# For port 53
sudo systemctl disable systemd-resolved
sudo systemctl stop systemd-resolved
sudo systemctl mask systemd-resolved



############################################################################
## Backup default config
# Check if backup is already made
backup_location=$(pwd)/backup
if [ -f "$backup_location/" ]; then
    echo "${RED}There is already a backup of the default configs. Change the name of the backup folder or delete it${NOCOLOR}"
    exit 1
else
    # make backup folder
    sudo mkdir "$backup_location"

    # backup all default config
    sudo cp /etc/dhcpcd.conf "$backup_location"
    sudo cp /etc/dnsmasq.conf "$backup_location"
    sudo cp /etc/default/hostapd "$backup_location"
    sudo cp /etc/sysctl.conf "$backup_location"
    sudo cp /etc/rc.local "$backup_location"
fi



############################################################################
### Configure the Access point
## Configure DHCPCD
sudo cat > /etc/dhcpcd.conf << EOF
interface wlan0
        static ip_address=192.168.0.0/24
        denyinterfaces wlan0
        nohook wpa supplicant

interface wlan1
        static ip_address=172.168.1.0/24
        denyinterfaces wlan1
        nohook wpa_supplicant
EOF
# Apply changes
sudo systemctl restart dhcpcd

## Configure interfaces
sudo cat > /etc/network/interfaces << EOF
# Internet
auto eth0
iface eth0 inet dhcp

# AP0 (wlan0)
auto wlan0
iface wlan0 inet static
    address 192.168.0.1
    netmask 255.255.255.0
    # dns-nameservers 8.8.8.8 1.1.1.1

# AP1 (wlan1)
auto wlan1
iface wlan1 inet static
    address 172.168.1.1
    netmask 255.255.255.0
    # dns-nameservers 8.8.8.8 1.1.1.1
EOF

## Configure DNSMASQ
sudo cat > /etc/dnsmasq.d/dnsmasq-wlan0.conf << EOF
# Set listening address
listen-address=192.168.0.1

# Set the domain
domain=WellnessAlliantie-sauna.local

# Set the wifi interface
interface=wlan0

# Set the ip range that can be given to clients and lease time
dhcp-range=192.168.0.10,192.168.0.200,12h

# Set the gateway IP address
dhcp-option=wlan0,3,192.168.0.1

# Set dns server address
# dhcp-option=6,192.168.0.1,6.6.6.6
dhcp-option=6,1.1.1.1,8.8.8.8

# Redirect all requests to google.com
# address=/#/8.8.8.8

# Redirect request to google.com
#server=8.8.8.8
#server=1.1.1.1
EOF

sudo cat > /etc/dnsmasq.d/dnsmasq-wlan1.conf << EOF
# Set listening address
listen-address=172.168.1.1

# Set the domain
domain=IoT-WellnessAlliantie-sauna.local

# Set the wifi interface
interface=wlan1

# Set the ip range that can be given to clients and lease time
dhcp-range=172.168.1.10,172.168.1.200,12h

# Set the gateway IP address
dhcp-option=wlan1,3,172.168.1.1

# Set dns server address
# dhcp-option=6,192.168.0.1,6.6.6.6
dhcp-option=6,1.1.1.1,8.8.8.8

# Redirect all requests to google.com
# address=/#/8.8.8.8

# Redirect request to google.com
#server=8.8.8.8
#server=1.1.1.1
EOF


# Apply changes
sudo systemctl start dnsmasq


## Configure HOSTAPD
# Config for HOSTAPD
sudo cat > /etc/hostapd/wlan0.conf << EOF
interface=wlan0
driver=nl80211
ieee80211n=1
ssid=WellnessAlliantie-sauna_wifi
hw_mode=g
channel=10
wmm_enabled=0
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=sauna-wifi-2012!
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

sudo cat > /etc/hostapd/wlan1.conf << EOF
interface=wlan1
driver=nl80211
ieee80211n=1
ssid=IoT-netwerk
hw_mode=g
channel=10
wmm_enabled=0
ignore_broadcast_ssid=1
wpa=2
wpa_passphrase=Plasma9-Colossal-Amplify
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

# Get HOSTAPD ready to run
systemctl enable --now hostapd@wlan0
systemctl enable --now hostapd@wlan1


## ROUTING
# Enabling IPv4 forwarding
sudo sed -i 's,#net.ipv4.ip_forward=1,net.ipv4.ip_forward=1,' /etc/sysctl.conf
sudo echo "net.ipv4.conf.all.forwarding=1" >> /etc/sysctl.conf


# iptable rules
# Route everything
# Rules for connected to internet
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
sudo iptables -A FORWARD -i eth0 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i wlan0 -o eth0 -j ACCEPT
sudo iptables -A FORWARD -i eth0 -o wlan1 -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i wlan1 -o eth0 -j ACCEPT

sudo iptables -A INPUT -i wlan1 -s 172.168.1.0/24 -p tcp --dport 80 -j DROP
sudo iptables -A INPUT -i wlan1 -s 172.168.1.0/24 -p tcp --dport 8554 -j DROP


# Save the IPTables rules
sudo iptables-save
sudo netfilter-persistent save



# End message for configuration of router/AP/firewall
echo -e "${GREEN}Your router/Access-Point/Firewall are installed and configured${NOCOLOR}"
sleep 3

# Security settings
## SSH
sudo sed -i 's,#Port 22,Port 2048,' /etc/ssh/sshd_config
sudo sed -i 's,#SyslogFacility AUTH,SyslogFacility AUTH,' /etc/ssh/sshd_config
sudo sed -i 's,#LogLevel INFO,LogLevel INFO,' /etc/ssh/sshd_config



# Create user and make root
sudo useradd -m wa_admin
sudo usermod --shell /bin/bash wa_admin
echo "wa_admin:Kelp-Bovine-Sixties1" | chpasswd
echo "wa_admin ALL=(ALL) ALL" > /etc/sudoers.d/wa_admin
sudo chmod 0440 /etc/sudoers.d/wa_admin

# Disable root login
sudo usermod --shell /sbin/nologin root