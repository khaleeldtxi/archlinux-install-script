# Archlinux-Install-Script

The Archlinux-Install-Script allow the entire Arch Linux installation process to be automated.


## Features
Btrfs - Subvolumes (Inspired by OpenSuse layout)  
Snapper  
KDE-Plasma  
Wayland  
Nvidia



## Steps

Boot Arch Linux ISO  

pacman -Sy git

git clone https://github.com/khaleeldtxi/archlinux-install-script/

cd archlinux-install-script/  

chmod a+x archlinux_raw.sh && sh archlinux_raw.sh


Enter the following when asked:

*Username\
*Password\
*Hostname\
*Keymap\
*Locale (in format en_US)\
*Select Kernel (Stable, Hardened, LTS, Zen)\
*Select Disk (example /dev/sda or /dev/nvmeon1) - EFI & Root parition will be created

Then the script will automate the installation process.

Post installation, reboot and run the following commands:\
\
sudo firewall-cmd --zone=home --add-service kdeconnect --permanent\
sudo systemctl enable --now virtlogd.socket\
sudo virsh net-start default\
sudo virsh net-autostart default


