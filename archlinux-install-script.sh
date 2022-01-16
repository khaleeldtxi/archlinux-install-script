#!/usr/bin/env -S bash -e

# Cleaning the TTY
clear

timedatectl set-ntp true &>/dev/null

# Update mirrors
reflector --verbose --country 'Germany' -l 5 --sort rate --save /etc/pacman.d/mirrorlist
pacman -Syy

# Installing curl
pacman -S --noconfirm curl

# Enter username
read -r -p "Please enter username for a user account (leave empty to skip): " username

# Enter password for $username
read -r -p "Please enter password for $username (leave empty to skip): " password

# Enter hostname
read -r -p "Please enter the hostname: " hostname

# Enter locale
read -r -p "Please insert the locale you use in this format (en_US): " locale

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

# Checking the microcode to install
CPU=$(grep vendor_id /proc/cpuinfo)
if [[ $CPU == *"AuthenticAMD"* ]]; then
    microcode=amd-ucode
else
    microcode=intel-ucode
fi

echo "-------select your disk to format----------------"
lsblk
echo "Please enter disk: (example /dev/sda or /dev/nvmeon1)"
read DISK
echo -e "\nFormatting disk...\n$HR"
echo "--------------------------------------"

# disk prep
sgdisk -Z ${DISK} # zap all on disk
sgdisk -a 2048 -o ${DISK} # new gpt disk 2048 alignment

# create partitions
sgdisk -n 1:0:+512M ${DISK} # partition 1 (UEFI SYS), default start block, 512MB
sgdisk -n 2:0:0     ${DISK} # partition 2 (Root), default start, remaining

# set partition types
sgdisk -t 1:ef00 ${DISK}
sgdisk -t 2:8300 ${DISK}

# label partitions
sgdisk -c 1:"EFI" ${DISK}
sgdisk -c 2:"ROOT" ${DISK}

ESP=${DISK}1
BTRFS=${DISK}2

# Formatting the ESP as FAT32
echo -e "\nFormatting the EFI Partition as FAT32.\n$HR"
mkfs.fat -F 32 -n "EFI" "${DISK}1"

# Formatting the partition as BTRFS
echo "Formatting the Root partition as BTRFS."
mkfs.btrfs -L ARCH-ROOT -f -n 32k "$BTRFS"
mount $BTRFS /mnt

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
pacstrap /mnt base base-devel ${kernel} ${microcode} ${kernel}-headers linux-firmware grub grub-btrfs snapper snap-pac efibootmgr sudo networkmanager network-manager-applet nano firewalld zram-generator reflector mlocate man-db bash-completion btrfs-progs dosfstools os-prober sysfsutils usbutils e2fsprogs mtools inetutils less man-pages texinfo vim git bluez sddm which tree --noconfirm --needed

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

# Setting user password
[ -n "$username" ] && echo "Setting user password for ${username}." && arch-chroot /mnt /bin/passwd "$username", $password

# Giving wheel user sudo access
sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/g' /mnt/etc/sudoers

# Change audit logging group
echo "log_group = audit" >> /etc/audit/auditd.conf

# Enabling audit service
systemctl enable auditd --root=/mnt &>/dev/null

# Enabling auto-trimming service
systemctl enable fstrim.timer --root=/mnt &>/dev/null

# Enabling NetworkManager
echo "Enabling NetworkManager"
systemctl enable NetworkManager --root=/mnt &>/dev/null

# Enabling SDDM
echo "Enabling sddm"
systemctl enable sddm --root=/mnt &>/dev/null

# Enabling AppArmor
echo "Enabling AppArmor."
systemctl enable apparmor --root=/mnt &>/dev/null

# Enabling Firewalld
echo "Enabling Firewalld."
systemctl enable firewalld --root=/mnt &>/dev/null

# Enabling Reflector timer
echo "Enabling Reflector."
systemctl enable reflector.timer --root=/mnt &>/dev/null

# Enabling systemd-oomd
echo "Enabling systemd-oomd."
systemctl enable systemd-oomd --root=/mnt &>/dev/null

# Enabling Snapper automatic snapshots
echo "Enabling Snapper and automatic snapshots entries."
systemctl enable snapper-timeline.timer --root=/mnt &>/dev/null
systemctl enable snapper-cleanup.timer --root=/mnt &>/dev/null
systemctl enable grub-btrfs.path --root=/mnt &>/dev/null

# Setting umask to 077
sed -i 's/022/077/g' /mnt/etc/profile
echo "" >> /mnt/etc/bash.bashrc
echo "umask 077" >> /mnt/etc/bash.bashrc

# Pacman eye-candy features
print "Enabling colours and animations in pacman."
sed -i 's/#Color/Color\nILoveCandy/' /mnt/etc/pacman.conf
sed -i 's/#VerbosePkgLists/VerbosePkgLists/' /mnt/etc/pacman.conf
sed -i 's/#ParallelDownloads = 5/ParallelDownloads = 5/' /mnt/etc/pacman.conf


# Finishing up
echo "Done, you may now wish to reboot (further changes can be done by chrooting into /mnt)."
exit

