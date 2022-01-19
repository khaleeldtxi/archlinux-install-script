#!/usr/bin/env -S bash -e

#-------------------------------------------------------------------------
#                     █████╗ ██████╗  ██████╗██╗  ██╗
#                    ██╔══██╗██╔══██╗██╔════╝██║  ██║
#                    ███████║██████╔╝██║     ███████║ 
#                    ██╔══██║██╔══██╗██║     ██╔══██║ 
#                    ██║  ██║██║  ██║╚██████╗██║  ██║ 
#                    ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝ 
#-------------------------------------------------------------------------

setfont ter-v22b
clear

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# set up a config file
CONFIG_FILE=$SCRIPT_DIR/setup.conf
if [ ! -f $CONFIG_FILE ]; then # check if file exists
    touch -f $CONFIG_FILE # create file if not exists
fi

# set options in setup.conf
set_option() {
    if grep -Eq "^${1}.*" $CONFIG_FILE; then # check if option exists
        sed -i -e "/^${1}.*/d" $CONFIG_FILE # delete option if exists
    fi
    echo "${1}=${2}" >>$CONFIG_FILE # add option
}

logo () {
# This will be shown on every set as user is progressing
echo -ne "
-------------------------------------------------------------------------
                     █████╗ ██████╗  ██████╗██╗  ██╗
                    ██╔══██╗██╔══██╗██╔════╝██║  ██║
                    ███████║██████╔╝██║     ███████║ 
                    ██╔══██║██╔══██╗██║     ██╔══██║ 
                    ██║  ██║██║  ██║╚██████╗██║  ██║ 
                    ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝   
------------------------------------------------------------------------
            Please select presetup settings for your system              
------------------------------------------------------------------------
"
}

logo

timedatectl set-ntp true &>/dev/null

# Setting up mirrors for optimal download

sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
pacman -S --noconfirm curl pacman-contrib terminus-font reflector rsync grub gptfdisk btrfs-progs
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup

echo -ne "
-------------------------------------------------------------------------
                    Setting up $iso mirrors for faster downloads
-------------------------------------------------------------------------
"

iso=$(curl -4 ifconfig.co/country-iso)

# Update mirrors
reflector --verbose --country $iso -f 5 -l 20 --sort rate --save /etc/pacman.d/mirrorlist
pacman -Syy

userinfo () {
# Enter username
read -p "Please enter your username: " username
set_option USERNAME ${username,,} # convert to lower case

# Enter password for root & $username
echo -ne "Please enter your password for $username: \n"
read -s password # read password without echo
set_option PASSWORD $password

echo -ne "Please enter your password for root account: \n"
read -s root_password
#set_option ROOT_PASSWORD $root_password

# Enter hostname
read -rep "Please enter your hostname: " hostname
set_option hostname $hostname
}

userinfo

clear

timezone () {
# Added this from arch wiki https://wiki.archlinux.org/title/System_time
time_zone="$(curl --fail https://ipapi.co/timezone)"
echo -ne "System detected your timezone to be '$time_zone' \n"
echo -ne "Is this correct? yes/no:" 
read answer
case $answer in
    y|Y|yes|Yes|YES)
    set_option TIMEZONE $time_zone;;
    n|N|no|NO|No)
    echo "Please enter your desired timezone e.g. Asia/Kolkata :" 
    read new_timezone
    set_option TIMEZONE $new_timezone;;
    *) echo "Wrong option. Try again";timezone;;
esac
}
timezone

clear

keymap () {
# These are default key maps as presented in official arch repo archinstall
echo -ne "
Please select key board layout from this list
    -by
    -ca
    -cf
    -cz
    -de
    -dk
    -es
    -et
    -fa
    -fi
    -fr
    -gr
    -hu
    -il
    -it
    -lt
    -lv
    -mk
    -nl
    -no
    -pl
    -ro
    -ru
    -sg
    -ua
    -uk
    -us

"
read -p "Your key boards layout:" keymap
set_option KEYMAP $keymap
}

keymap

# Enter locale
read -r -p "Please insert the locale you use (in this format: en_US): " locale

# Selecting the kernel flavor to install
kernel_selector () {
    echo "List of kernels:"
    echo "1) Stable — Vanilla Linux kernel and modules, with a few patches applied."
    echo "2) Hardened — A security-focused Linux kernel."
    echo "3) Longterm — Long-term support (LTS) Linux kernel and modules."
    echo "4) Zen Kernel — Optimized for desktop usage."
    read -r -p "Insert the number of the corresponding kernel: " choice
    echo "$choice will be installed"
    case $choice in
        1 ) kernel=linux
            ;;
        2 ) kernel=linux-hardened
            ;;
        3 ) kernel=linux-lts
            ;;
        4 ) kernel=linux-zen
            ;;
        * ) echo "You did not enter a valid selection."
            kernel_selector
    esac
}

kernel_selector

clear

# Checking the microcode to install
CPU=$(grep vendor_id /proc/cpuinfo)
if [[ $CPU == *"AuthenticAMD"* ]]; then
    microcode=amd-ucode
else
    microcode=intel-ucode
fi

drivessd () {
echo -ne "
Is this an ssd? yes/no:
"
read ssd_drive

case $ssd_drive in
    y|Y|yes|Yes|YES)
    echo "mountoptions=lazytime,relatime,compress=zstd,space_cache=v2,ssd,commit=120" >> setup.conf;;
    n|N|no|NO|No)
    echo "mountoptions=lazytime,relatime,compress=zstd,space_cache=v2,commit=120" >> setup.conf;;
    *) echo "Wrong option. Try again";drivessd;;
esac
}

# show disks present on system
lsblk -n --output TYPE,KNAME,SIZE | awk '$1=="disk"{print NR,"/dev/"$2" - "$3}' # show disks with /dev/ prefix and size
echo -ne "
-------------------------------------------------------------------------
                    Formating Disk
-------------------------------------------------------------------------
         THIS WILL FORMAT AND DELETE ALL DATA ON THE DISK             
        Please make sure you know what you are doing because         
     after formating your disk there is no way to get data back      
------------------------------------------------------------------------
                select your disk to format
-------------------------------------------------------------------------
"

echo "Please enter path to disk: (example /dev/sda or /dev/nvmeon1)"
read DISK


clear

echo -ne "
-------------------------------------------------------------------------
                    Formating Disk
-------------------------------------------------------------------------

# disk prep
sgdisk -Z ${DISK} # zap all on disk
sgdisk -a 2048 -o ${DISK} # new gpt disk 2048 alignment

# create partitions
sgdisk -n 1:0:+1024M ${DISK} # partition 1 (UEFI), default start block, 1024MB
sgdisk -n 2:0:0     ${DISK} # partition 2 (Root), default start, remaining

# set partition types
sgdisk -t 1:ef00 ${DISK}
sgdisk -t 2:8300 ${DISK}

# label partitions
sgdisk -c 1:"EFI" ${DISK}
sgdisk -c 2:"ROOT" ${DISK}

# make filesystems
echo -ne "
-------------------------------------------------------------------------
                    Creating Filesystems
-------------------------------------------------------------------------

if [[ "${DISK}" =~ "nvme" ]]; then
    EFI=${DISK}p1
    BTRFS=${DISK}p2
else
    EFI=${DISK}1
    BTRFS=${DISK}2
fi

# Formatting the ESP as FAT32
echo -e "\nFormatting the EFI Partition as FAT32.\n$HR"
mkfs.fat -F 32 -n "EFI" "${EFI}"

# Formatting the partition as BTRFS
echo "Formatting the Root partition as BTRFS."
wipefs -af "$BTRFS" &>/dev/null
mkfs.btrfs -L ARCH-ROOT -f -n 32k "$BTRFS"
mount -t btrfs $BTRFS /mnt

# Creating BTRFS subvolumes
echo "Creating BTRFS subvolumes."
btrfs subvolume create /mnt/@ &>/dev/null
btrfs subvolume create /mnt/@/.snapshots &>/dev/null
mkdir /mnt/@/.snapshots/1 &>/dev/null
btrfs subvolume create /mnt/@/.snapshots/1/snapshot &>/dev/null
btrfs subvolume create /mnt/@/boot &>/dev/null
btrfs subvolume create /mnt/@/home &>/dev/null
btrfs subvolume create /mnt/@/root &>/dev/null
btrfs subvolume create /mnt/@/srv &>/dev/null
btrfs subvolume create /mnt/@/var_log &>/dev/null
btrfs subvolume create /mnt/@/var_log_journal &>/dev/null
btrfs subvolume create /mnt/@/var_cache &>/dev/null
btrfs subvolume create /mnt/@/var_crash &>/dev/null
btrfs subvolume create /mnt/@/var_tmp &>/dev/null
btrfs subvolume create /mnt/@/var_spool &>/dev/null
btrfs subvolume create /mnt/@/var_lib_libvirt_images &>/dev/null
btrfs subvolume create /mnt/@/var_lib_machines &>/dev/null

chattr +C /mnt/@/boot
chattr +C /mnt/@/srv
chattr +C /mnt/@/var_log
chattr +C /mnt/@/var_log_journal
chattr +C /mnt/@/var_crash
chattr +C /mnt/@/var_cache
chattr +C /mnt/@/var_tmp
chattr +C /mnt/@/var_spool
chattr +C /mnt/@/var_lib_libvirt_images
chattr +C /mnt/@/var_lib_machines

#Set the default BTRFS Subvol to Snapshot 1 before pacstrapping
btrfs subvolume set-default "$(btrfs subvolume list /mnt | grep "@/.snapshots/1/snapshot" | grep -oP '(?<=ID )[0-9]+')" /mnt

DATE=`date +"%Y-%m-%d %H:%M:%S"`

cat << EOF >> /mnt/@/.snapshots/1/info.xml
<?xml version="1.0"?>
<snapshot>
  <type>single</type>
  <num>1</num>
  <date>$DATE</date>
  <description>First Root Filesystem</description>
  <cleanup>number</cleanup>
</snapshot>
EOF

chmod 600 /mnt/@/.snapshots/1/info.xml

# Mounting the newly created subvolumes
umount /mnt
echo "Mounting the newly created subvolumes."
mount -o lazytime,relatime,compress=zstd,space_cache=v2,ssd $BTRFS /mnt
mkdir -p /mnt/{boot,root,home,.snapshots,srv,tmp,/var/log,/var/crash,/var/cache,/var/tmp,/var/spool,/var/lib/libvirt/images,/var/lib/machines}
mount -o lazytime,relatime,compress=zstd,space_cache=v2,autodefrag,ssd,discard=async,nodev,nosuid,noexec,subvol=@/boot $BTRFS /mnt/boot
mount -o lazytime,relatime,compress=zstd,space_cache=v2,autodefrag,ssd,discard=async,nodev,nosuid,subvol=@/root $BTRFS /mnt/root
mount -o lazytime,relatime,compress=zstd,space_cache=v2,autodefrag,ssd,discard=async,nodev,nosuid,subvol=@/home $BTRFS /mnt/home
mount -o lazytime,relatime,compress=zstd,space_cache=v2,autodefrag,ssd,discard=async,subvol=@/.snapshots $BTRFS /mnt/.snapshots
mount -o lazytime,relatime,compress=zstd,space_cache=v2,autodefrag,ssd,discard=async,subvol=@/srv $BTRFS /mnt/srv
mount -o lazytime,relatime,compress=zstd,space_cache=v2,autodefrag,ssd,discard=async,nodatacow,nodev,nosuid,noexec,subvol=@/var_log $BTRFS /mnt/var/log
mkdir -p /mnt/var/log/journal
mount -o lazytime,relatime,compress=zstd,space_cache=v2,autodefrag,ssd,discard=async,nodatacow,subvol=@/var_log_journal $BTRFS /mnt/var/log/journal
mount -o lazytime,relatime,compress=zstd,space_cache=v2,autodefrag,ssd,discard=async,nodatacow,nodev,nosuid,noexec,subvol=@/var_crash $BTRFS /mnt/var/crash
mount -o lazytime,relatime,compress=zstd,space_cache=v2,autodefrag,ssd,discard=async,nodatacow,nodev,nosuid,noexec,subvol=@/var_cache $BTRFS /mnt/var/cache
mount -o lazytime,relatime,compress=zstd,space_cache=v2,autodefrag,ssd,discard=async,nodatacow,nodev,nosuid,subvol=@/var_tmp $BTRFS /mnt/var/tmp
mount -o lazytime,relatime,compress=zstd,space_cache=v2,autodefrag,ssd,discard=async,nodatacow,nodev,nosuid,noexec,subvol=@/var_spool $BTRFS /mnt/var/spool
mount -o lazytime,relatime,compress=zstd,space_cache=v2,autodefrag,ssd,discard=async,nodatacow,nodev,nosuid,noexec,subvol=@/var_lib_libvirt_images $BTRFS /mnt/var/lib/libvirt/images
mount -o lazytime,relatime,compress=zstd,space_cache=v2,autodefrag,ssd,discard=async,nodatacow,nodev,nosuid,noexec,subvol=@/var_lib_machines $BTRFS /mnt/var/lib/machines

mkdir -p /mnt/boot/efi
mount -o nodev,nosuid,noexec $ESP /mnt/boot/efi


# Pacstrap (setting up a base sytem onto the new root)
echo "Installing the base system (it may take a while)."
pacstrap /mnt base base-devel ${kernel} ${microcode} ${kernel}-headers linux-firmware terminus-font grub grub-btrfs snapper snap-pac efibootmgr sudo networkmanager network-manager-applet nano firewalld zram-generator reflector mlocate man-db bash-completion btrfs-progs dosfstools os-prober sysfsutils usbutils e2fsprogs mtools inetutils less man-pages texinfo vim git bluez sddm which tree --noconfirm --needed

#pacstrap /mnt nvidia nvidia-utils nvidia-settings nvidia-dkms xorg-server-devel plasma-meta sddm wireless_tools wpa_supplicant kde-graphics-meta kde-multimedia-meta kde-network-meta kde-pim-meta kde-sdk-meta kde-system-meta kde-utilities-meta plasma-wayland-session egl-wayland qt5-wayland qt6-wayland apparmor python-psutil pipewire-pulse pipewire-alsa pipewire-jack flatpak adobe-source-han-sans-otc-fonts adobe-source-han-serif-otc-fonts gnu-free-fonts bluez-utils xdg-utils xdg-user-dirs ntfs-3g neofetch wget openssh cronie curl htop p7zip zsh zsh-autosuggestions zsh-syntx-highlighting --noconfirm --needed

echo "/usr/lib/pipewire-0.3/jack" > /mnt/etc/ld.so.conf.d/pipewire-jack.conf

# Generating /etc/fstab
echo "Generating a new fstab."
genfstab -U -p /mnt >> /mnt/etc/fstab
sed -i 's#,subvolid=258,subvol=/@/.snapshots/1/snapshot,subvol=@/.snapshots/1/snapshot##g' /mnt/etc/fstab

# Setting hostname
echo "$hostname" > /mnt/etc/hostname

# Setting hosts file
echo "Setting hosts file."
cat > /mnt/etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $hostname.localdomain   $hostname
EOF

# Setting up locales
echo "$locale.UTF-8 UTF-8"  > /mnt/etc/locale.gen
echo "LANG=$locale.UTF-8" > /mnt/etc/locale.conf

# Configuring /etc/mkinitcpio.conf
echo "Configuring /etc/mkinitcpio for ZSTD compression."
sed -i 's,#COMPRESSION="zstd",COMPRESSION="zstd",g' /mnt/etc/mkinitcpio.conf

sed -i 's#rootflags=subvol=${rootsubvol}##g' /mnt/etc/grub.d/10_linux
sed -i 's#rootflags=subvol=${rootsubvol}##g' /mnt/etc/grub.d/20_linux_xen

# Enabling CPU Mitigations
curl https://raw.githubusercontent.com/Whonix/security-misc/master/etc/default/grub.d/40_cpu_mitigations.cfg >> /mnt/etc/grub.d/40_cpu_mitigations

# Distrusting the CPU
curl https://raw.githubusercontent.com/Whonix/security-misc/master/etc/default/grub.d/40_distrust_cpu.cfg >> /mnt/etc/grub.d/40_distrust_cpu

# Enabling IOMMU
curl https://raw.githubusercontent.com/Whonix/security-misc/master/etc/default/grub.d/40_enable_iommu.cfg >> /mnt/etc/grub.d/40_enable_iommu

# Setting GRUB configuration file permissions
chmod 755 /mnt/etc/grub.d/*

# Configure AppArmor Parser caching
sed -i 's/#write-cache/write-cache/g' /mnt/etc/apparmor/parser.conf
sed -i 's,#Include /etc/apparmor.d/,Include /etc/apparmor.d/,g' /mnt/etc/apparmor/parser.conf

# Blacklisting kernel modules
curl https://raw.githubusercontent.com/Whonix/security-misc/master/etc/modprobe.d/30_security-misc.conf >> /mnt/etc/modprobe.d/30_security-misc.conf
chmod 600 /mnt/etc/modprobe.d/*

# Security kernel settings
curl https://raw.githubusercontent.com/Whonix/security-misc/master/etc/sysctl.d/30_security-misc.conf >> /mnt/etc/sysctl.d/30_security-misc.conf
sed -i 's/kernel.yama.ptrace_scope=2/kernel.yama.ptrace_scope=3/g' /mnt/etc/sysctl.d/30_security-misc.conf
curl https://raw.githubusercontent.com/Whonix/security-misc/master/etc/sysctl.d/30_silent-kernel-printk.conf >> /mnt/etc/sysctl.d/30_silent-kernel-printk.conf
chmod 600 /mnt/etc/sysctl.d/*

# IO udev rules
curl https://gitlab.com/garuda-linux/themes-and-settings/settings/garuda-common-settings/-/raw/master/etc/udev/rules.d/50-sata.rules > /mnt/etc/udev/rules.d/50-sata.rules
curl https://gitlab.com/garuda-linux/themes-and-settings/settings/garuda-common-settings/-/raw/master/etc/udev/rules.d/60-ioschedulers.rules > /etc/udev/rules.d/60-ioschedulers.rules
chmod 600 /mnt/etc/udev/rules.d/*

# Remove nullok from system-auth
sed -i 's/nullok//g' /mnt/etc/pam.d/system-auth

# Disable coredump
echo "* hard core 0" >> /mnt/etc/security/limits.conf


# Disable su for non-wheel users
bash -c 'cat > /mnt/etc/pam.d/su' <<-'EOF'
#%PAM-1.0
auth		sufficient	pam_rootok.so
# Uncomment the following line to implicitly trust users in the "wheel" group.
#auth		sufficient	pam_wheel.so trust use_uid
# Uncomment the following line to require a user to be in the "wheel" group.
auth		required	pam_wheel.so use_uid
auth		required	pam_unix.so
account		required	pam_unix.so
session		required	pam_unix.so
EOF

# ZRAM configuration
bash -c 'cat > /mnt/etc/systemd/zram-generator.conf' <<-'EOF'
[zram0]
zram-fraction = 1
max-zram-size = 8192
EOF

# Randomize Mac Address
bash -c 'cat > /mnt/etc/NetworkManager/conf.d/00-macrandomize.conf' <<-'EOF'
[device]
wifi.scan-rand-mac-address=yes
[connection]
wifi.cloned-mac-address=random
ethernet.cloned-mac-address=random
connection.stable-id=${CONNECTION}/${BOOT}
EOF

chmod 600 /mnt/etc/NetworkManager/conf.d/00-macrandomize.conf

# Enable IPv6 privacy extensions
bash -c 'cat > /mnt/etc/NetworkManager/conf.d/ip6-privacy.conf' <<-'EOF'
[connection]
ipv6.ip6-privacy=2
EOF

chmod 600 /mnt/etc/NetworkManager/conf.d/ip6-privacy.conf

# Configuring the system.
arch-chroot /mnt /bin/bash -e <<EOF
# Setting up timezone
ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime &>/dev/null

# Setting up clock
hwclock --systohc

 # Generating locales.my keys aren't even on
echo "Generating locales."
locale-gen &>/dev/null

# Generating a new initramfs
echo "Creating a new initramfs."
chmod 600 /boot/initramfs-linux* &>/dev/null
mkinitcpio -P &>/dev/null

# Snapper configuration
echo "Configuring Snapper"
umount /.snapshots
rm -r /.snapshots
snapper --no-dbus -c root create-config /
btrfs subvolume delete /.snapshots
mkdir /.snapshots
mount -a
chmod 750 /.snapshots

# Installing GRUB
echo "Installing GRUB on /boot/efi."
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --modules="normal test efi_gop efi_uga search echo linux all_video gfxmenu gfxterm_background gfxterm_menu gfxterm loadenv configfile gzio part_gpt gcry_rijndael gcry_sha256 btrfs" --disable-shim-lock

# Creating grub config file.
echo "Creating GRUB config file."
grub-mkconfig -o /boot/grub/grub.cfg

# Adding user with sudo privilege
if [ -n "$username" ]; then
    echo "Adding $username with root privilege."
    useradd -m $username
    usermod -aG wheel $username
    groupadd -r audit
    gpasswd -a $username audit
fi
EOF

# Enable AppArmor notifications
# Must create ~/.config/autostart first
mkdir -p -m 700 /mnt/home/${username}/.config/autostart/
bash -c "cat > /mnt/home/${username}/.config/autostart/apparmor-notify.desktop" <<-'EOF'
[Desktop Entry]
Type=Application
Name=AppArmor Notify
Comment=Receive on screen notifications of AppArmor denials
TryExec=aa-notify
Exec=aa-notify -p -s 1 -w 60 -f /var/log/audit/audit.log
StartupNotify=false
NoDisplay=true
EOF

chmod 700 /mnt/home/${username}/.config/autostart/apparmor-notify.desktop
arch-chroot /mnt chown -R $username:$username /home/${username}/.config

# Setting root & user password
echo -en "$root_password\n$root_password" | passwd
[ -n "$username" ] && echo "Setting user password for ${username}." && arch-chroot /mnt /bin/passwd "$username", $password

# Giving wheel user sudo access
sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/g' /etc/sudoers

# Change audit logging group
echo "log_group = audit" >> /etc/audit/auditd.conf

# Enabling audit service
systemctl enable auditd

# Enabling auto-trimming service
systemctl enable fstrim.timer

# Enabling NetworkManager
echo "Enabling NetworkManager"
systemctl enable NetworkManager

# Enabling SDDM
echo "Enabling sddm"
systemctl enable sddm

# Enabling AppArmor
echo "Enabling AppArmor."
systemctl enable apparmor

# Enabling Firewalld
echo "Enabling Firewalld."
systemctl enable firewalld
sudo firewall-cmd --zone=home --add-service kdeconnect --permanent

# Enabling Reflector timer
echo "Enabling Reflector."
systemctl enable reflector.timer

# Enabling systemd-oomd
echo "Enabling systemd-oomd."
systemctl enable systemd-oomd

# Enabling Snapper automatic snapshots
echo "Enabling Snapper and automatic snapshots entries."
systemctl enable snapper-timeline.timer
systemctl enable snapper-cleanup.timer
systemctl enable grub-btrfs.path

# Setting umask to 077
sed -i 's/022/077/g' /etc/profile
echo "" >> /etc/bash.bashrc
echo "umask 077" >> /etc/bash.bashrc

# Pacman eye-candy features
print "Enabling colours and animations in pacman."
sed -i 's/#Color/Color\nILoveCandy/' /mnt/etc/pacman.conf
sed -i 's/#VerbosePkgLists/VerbosePkgLists/' /mnt/etc/pacman.conf
sed -i 's/#ParallelDownloads = 5/ParallelDownloads = 5/' /mnt/etc/pacman.conf
sed -i '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf
pacman -Sy --noconfirm

sed -i 's/#MAKEFLAGS="-j2"/MAKEFLAGS="-j$(nproc)"/g; s/-)/--threads=0 -)/g; s/gzip/pigz/g; s/bzip2/pbzip2/g' /etc/makepkg.conf
journalctl --vacuum-size=100M --vacuum-time=2weeks

touch /etc/sysctl.d/99-swappiness.conf
echo 'vm.swappiness=20' > /etc/sysctl.d/99-swappiness.conf

#Install paru
echo "Paru (AUR package helper) installation"
git clone https://aur.archlinux.org/paru-bin.git
cd paru-bin/ || exit
makepkg -sirc
cd "$HOME" || exit

touch "~/.cache/zshhistory"
git clone "https://github.com/ChrisTitusTech/zsh"
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ~/powerlevel10k
ln -s "~/zsh/.zshrc" ~/.zshrc

export PATH=$PATH:~/.local/bin
cp -r ~/ArchRaw/dotfiles/* ~/.config/
pip install konsave
konsave -i ~/ArchRaw/kde.knsv
sleep 1
konsave -a kde

echo -e "Installing CyberRe Grub theme..."
THEME_DIR="/boot/grub/themes"
THEME_NAME=CyberRe
echo -e "Creating the theme directory..."
mkdir -p "${THEME_DIR}/${THEME_NAME}"
echo -e "Copying the theme..."
cd ${HOME}/ArchRaw
cp -a ${THEME_NAME}/* ${THEME_DIR}/${THEME_NAME}
echo -e "Backing up Grub config..."
cp -an /etc/default/grub /etc/default/grub.bak
echo -e "Setting the theme as the default..."
grep "GRUB_THEME=" /etc/default/grub 2>&1 >/dev/null && sed -i '/GRUB_THEME=/d' /etc/default/grub
echo "GRUB_THEME=\"${THEME_DIR}/${THEME_NAME}/theme.txt\"" >> /etc/default/grub
echo -e "Updating grub..."
grub-mkconfig -o /boot/grub/grub.cfg
echo -e "All set!"

rm -r /root/ArchRaw
rm -r /home/$USERNAME/ArchRaw

cd $pwd

# Finishing up
echo "Done, you may now wish to reboot (further changes can be done by chrooting into /mnt)."
exit