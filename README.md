# Archlinux-Install-Script

The Archlinux-Install-Script allow the entire Arch Linux installation process to be automated.


## Features
Btrfs - Subvolumes (Inspired from OpenSuse layout)  
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
*Host\
*Select Kernel (Stable, Hardened, LTS, Zen)\
*Select Disk (example /dev/sda or /dev/nvmeon1) - EFI & Root parition will be created\
*Locale (in format en_US)  
*Keymap
