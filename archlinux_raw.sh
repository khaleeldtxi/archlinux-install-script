#!/usr/bin/env -S bash -e

#-------------------------------------------------------------------------
#                     █████╗ ██████╗  ██████╗██╗  ██╗
#                    ██╔══██╗██╔══██╗██╔════╝██║  ██║
#                    ███████║██████╔╝██║     ███████║ 
#                    ██╔══██║██╔══██╗██║     ██╔══██║ 
#                    ██║  ██║██║  ██║╚██████╗██║  ██║ 
#                    ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝ 
#-------------------------------------------------------------------------
#--by Khaleel --inspired by tommytran732, Chris Titus, MatMoul and many others
#------------------------------------------------------------------------------
#"

setfont ter-v22b
clear

logo () {
# This will be shown on every set as user is progressing
echo -ne "
------------------------------------------------------------------------------
                     █████╗ ██████╗  ██████╗██╗  ██╗
                    ██╔══██╗██╔══██╗██╔════╝██║  ██║
                    ███████║██████╔╝██║     ███████║ 
                    ██╔══██║██╔══██╗██║     ██╔══██║ 
                    ██║  ██║██║  ██║╚██████╗██║  ██║ 
                    ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝   
------------------------------------------------------------------------------
                          --from Khaleel 
------------------------------------------------------------------------------
      --inspired by tommytran732, Chris Titus, MatMoul and many others
------------------------------------------------------------------------------
"
}

logo

timedatectl set-ntp true &>/dev/null

# Setting up mirrors for optimal download

cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup

iso=$(curl -4 ifconfig.co/country-iso)
echo -ne "
-------------------------------------------------------------------------
                    Setting up $iso mirrors for faster downloads
-------------------------------------------------------------------------
"

# Update mirrors
#reflector --verbose --country $iso -f 5 -l 20 --sort rate --save /etc/pacman.d/mirrorlist
reflector --verbose --country 'Germany' -l 5 --sort rate --save /etc/pacman.d/mirrorlist 
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
pacman -Syy --noconfirm curl pacman-contrib terminus-font reflector

clear

userinfo () {
# Enter username
read -p "Please enter your username: " username

# Enter password for root & $username
echo -ne "Please enter your password for $username: \n"
read -s password # read password without echo

echo -ne "Please enter your password for root account: \n"
read -s root_password

# Enter hostname
read -rep "Please enter your hostname: " hostname
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
    $time_zone;;
    n|N|no|NO|No)
    echo "Please enter your desired timezone e.g. Asia/Kolkata :" 
    read new_timezone;;
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
}

keymap

clear

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


logo


echo -ne "
-------------------------------------------------------------------------
                          Disk Preparation
-------------------------------------------------------------------------
"

# Selecting the target for the installation.
lsblk -n --output TYPE,KNAME,SIZE | awk '$1=="disk"{print NR,"/dev/"$2" - "$3}'
echo -ne "
------------------------------------------------------------------------
    THIS WILL FORMAT AND DELETE ALL DATA ON THE DISK             
    Please make sure you know what you are doing because         
    after formating your disk there is no way to get data back      
------------------------------------------------------------------------
"
read -p "Please enter full path to disk: (example /dev/sda or /dev/nvme0n1 or /dev/vda): " DISK


# disk prep
# Deleting old partition scheme.
read -r -p "This will delete the current partition table on $DISK. Do you agree [y/N]? " response
response=${response,,}
if [[ "$response" =~ ^(yes|y)$ ]]; then
    echo -ne "
    -------------------------------------------------------------------------
                                Formating Disk
    -------------------------------------------------------------------------
    "
    wipefs -af $DISK &>/dev/null
    sgdisk -Zo $DISK &>/dev/null
    
    # create partitions
    sgdisk -n 1:0:+1024M ${DISK} # partition 1 (UEFI), default start block, 1024MB
    sgdisk -n 2:0:-0     ${DISK} # partition 2 (Root), default start, remaining

    # set partition types
    sgdisk -t 1:ef00 ${DISK}
    sgdisk -t 2:8300 ${DISK}

    # label partitions
    sgdisk -c 1:"ESP" ${DISK}
    sgdisk -c 2:"ROOT" ${DISK}
else
    echo "Quitting."
    exit
fi


# make filesystems
echo -ne "
-------------------------------------------------------------------------
                          Creating Filesystems
-------------------------------------------------------------------------
"
partprobe "$DISK"

if [[ "${DISK}" =~ "nvme" ]]; then
    ESP=${DISK}p1
    BTRFS=${DISK}p2
else
    ESP=${DISK}1
    BTRFS=${DISK}2
fi

# Formatting the ESP as FAT32
echo -e "\nFormatting the EFI Partition as FAT32.\n$HR"
mkfs.fat -F 32 $ESP &>/dev/null

# Formatting the partition as BTRFS
echo "Formatting the Root partition as BTRFS."
mkfs.btrfs -L ARCH-ROOT -f -n 32k $BTRFS &>/dev/null
mount -t btrfs $BTRFS /mnt

# Creating BTRFS subvolumes

echo -ne "
-------------------------------------------------------------------------
                      Creating BTRFS subvolumes
-------------------------------------------------------------------------
"
btrfs subvolume create /mnt/@ &>/dev/null
btrfs subvolume create /mnt/@/.snapshots &>/dev/null
mkdir /mnt/@/.snapshots/1 &>/dev/null
btrfs subvolume create /mnt/@/.snapshots/1/snapshot &>/dev/null
mkdir /mnt/@/boot &>/dev/null
btrfs subvolume create /mnt/@/boot/grub &>/dev/null
btrfs subvolume create /mnt/@/home &>/dev/null
btrfs subvolume create /mnt/@/root &>/dev/null
btrfs subvolume create /mnt/@/srv &>/dev/null
mkdir /mnt/@/var &>/dev/null
btrfs subvolume create /mnt/@/var/log &>/dev/null
btrfs subvolume create /mnt/@/var/log/journal &>/dev/null
btrfs subvolume create /mnt/@/var/cache &>/dev/null
btrfs subvolume create /mnt/@/var/crash &>/dev/null
btrfs subvolume create /mnt/@/var/tmp &>/dev/null
btrfs subvolume create /mnt/@/var/spool &>/dev/null
mkdir -p /mnt/@/var/lib/libvirt &>/dev/null
btrfs subvolume create /mnt/@/var/lib/libvirt/images &>/dev/null
btrfs subvolume create /mnt/@/var/lib/machines &>/dev/null

chattr +C /mnt/@/srv
chattr +C /mnt/@/var/log
chattr +C /mnt/@/var/log/journal
chattr +C /mnt/@/var/cache
chattr +C /mnt/@/var/crash
chattr +C /mnt/@/var/tmp
chattr +C /mnt/@/var/spool
chattr +C /mnt/@/var/lib/libvirt/images
chattr +C /mnt/@/var/lib/machines

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
echo -ne "
-------------------------------------------------------------------------
                Mounting the newly created subvolumes
-------------------------------------------------------------------------
"
mount -o lazytime,relatime,compress=zstd,space_cache=v2,ssd $BTRFS /mnt
mkdir -p /mnt/{boot/grub,root,home,.snapshots,srv,tmp,/var/log,/var/crash,/var/cache,/var/tmp,/var/spool,/var/lib/libvirt/images,/var/lib/machines}
mount -o lazytime,relatime,compress=zstd,space_cache=v2,autodefrag,ssd,discard=async,nodev,nosuid,noexec,subvol=@/boot/grub $BTRFS /mnt/boot/grub
mount -o lazytime,relatime,compress=zstd,space_cache=v2,autodefrag,ssd,discard=async,nodev,nosuid,subvol=@/root $BTRFS /mnt/root
mount -o lazytime,relatime,compress=zstd,space_cache=v2,autodefrag,ssd,discard=async,nodev,nosuid,subvol=@/home $BTRFS /mnt/home
mount -o lazytime,relatime,compress=zstd,space_cache=v2,autodefrag,ssd,discard=async,subvol=@/.snapshots $BTRFS /mnt/.snapshots
mount -o lazytime,relatime,compress=zstd,space_cache=v2,autodefrag,ssd,discard=async,subvol=@/srv $BTRFS /mnt/srv
mount -o lazytime,relatime,compress=zstd,space_cache=v2,autodefrag,ssd,discard=async,nodatacow,nodev,nosuid,noexec,subvol=@/var/log $BTRFS /mnt/var/log
mkdir -p /mnt/var/log/journal
mount -o lazytime,relatime,compress=zstd,space_cache=v2,autodefrag,ssd,discard=async,nodatacow,subvol=@/var/log/journal $BTRFS /mnt/var/log/journal
mount -o lazytime,relatime,compress=zstd,space_cache=v2,autodefrag,ssd,discard=async,nodatacow,nodev,nosuid,noexec,subvol=@/var/crash $BTRFS /mnt/var/crash
mount -o lazytime,relatime,compress=zstd,space_cache=v2,autodefrag,ssd,discard=async,nodatacow,nodev,nosuid,noexec,subvol=@/var/cache $BTRFS /mnt/var/cache
mount -o lazytime,relatime,compress=zstd,space_cache=v2,autodefrag,ssd,discard=async,nodatacow,nodev,nosuid,subvol=@/var/tmp $BTRFS /mnt/var/tmp
mount -o lazytime,relatime,compress=zstd,space_cache=v2,autodefrag,ssd,discard=async,nodatacow,nodev,nosuid,noexec,subvol=@/var/spool $BTRFS /mnt/var/spool
mount -o lazytime,relatime,compress=zstd,space_cache=v2,autodefrag,ssd,discard=async,nodatacow,nodev,nosuid,noexec,subvol=@/var/lib/libvirt/images $BTRFS /mnt/var/lib/libvirt/images
mount -o lazytime,relatime,compress=zstd,space_cache=v2,autodefrag,ssd,discard=async,nodatacow,nodev,nosuid,noexec,subvol=@/var/lib/machines $BTRFS /mnt/var/lib/machines

mkdir -p /mnt/efi
mount -o nodev,nosuid,noexec $ESP /mnt/efi


echo -ne "
-------------------------------------------------------------------------
                      Installing the base system
-------------------------------------------------------------------------
"

# Pacstrap (setting up a base sytem onto the new root)
pacstrap /mnt base base-devel ${kernel} ${microcode} ${kernel}-headers linux-firmware grub grub-btrfs sudo networkmanager iptables-nft efibootmgr nano zram-generator reflector bash-completion btrfs-progs os-prober git curl apparmor terminus-font snapper snap-pac nano zsh zsh-doc grml-zsh-config zsh-autosuggestions zsh-completions zsh-history-substring-search zsh-syntax-highlighting zsh-lovers zsh-theme-powerlevel10k powerline firewalld dosfstools sysfsutils usbutils e2fsprogs vim git sddm which tree pipewire python-pip python-setuptools nvidia nvidia-utils nvidia-settings nvidia-dkms xorg-server-devel plasma-meta sddm wireless_tools wpa_supplicant kde-graphics-meta kde-multimedia-meta kde-network-meta kde-pim-meta kde-sdk-meta kde-system-meta kde-utilities-meta plasma-wayland-session egl-wayland qt5-wayland qt6-wayland bluez mtools inetutils less man-pages texinfo python-psutil pipewire-pulse pipewire-alsa pipewire-jack flatpak adobe-source-han-sans-otc-fonts adobe-source-han-serif-otc-fonts gnu-free-fonts bluez-utils xdg-utils xdg-user-dirs ntfs-3g neofetch wget openssh cronie htop p7zip mlocate man-db wireplumber firefox qemu virt-manager ebtables qemu-arch-extra edk2-ovmf dnsmasq bridge-utils swtpm --noconfirm --needed

# Routing jack2 through PipeWire.
echo "/usr/lib/pipewire-0.3/jack" > /mnt/etc/ld.so.conf.d/pipewire-jack.conf

# Generating /etc/fstab
echo "Generating a new fstab."
genfstab -U -p /mnt >> /mnt/etc/fstab
sed -i 's#,subvolid=258,subvol=/@/.snapshots/1/snapshot##g' /mnt/etc/fstab

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

# Setting up keyboard layout.
echo "KEYMAP=$keymap" > /mnt/etc/vconsole.conf

# Configuring /etc/mkinitcpio.conf
echo "Configuring /etc/mkinitcpio for ZSTD compression."
sed -i 's,#COMPRESSION="zstd",COMPRESSION="zstd",g' /mnt/etc/mkinitcpio.conf

echo -e "# Booting with BTRFS subvolume\nGRUB_BTRFS_OVERRIDE_BOOT_PARTITION_DETECTION=true" >> /mnt/etc/default/grub
sed -i 's#rootflags=subvol=${rootsubvol}##g' /mnt/etc/grub.d/10_linux
sed -i 's#rootflags=subvol=${rootsubvol}##g' /mnt/etc/grub.d/20_linux_xen

# Configure AppArmor Parser caching
sed -i 's/#write-cache/write-cache/g' /mnt/etc/apparmor/parser.conf
sed -i 's,#Include /etc/apparmor.d/,Include /etc/apparmor.d/,g' /mnt/etc/apparmor/parser.conf

# Enabling CPU Mitigations
curl https://raw.githubusercontent.com/Whonix/security-misc/master/etc/default/grub.d/40_cpu_mitigations.cfg >> /mnt/etc/grub.d/40_cpu_mitigations

# Distrusting the CPU
curl https://raw.githubusercontent.com/Whonix/security-misc/master/etc/default/grub.d/40_distrust_cpu.cfg >> /mnt/etc/grub.d/40_distrust_cpu

# Enabling IOMMU
curl https://raw.githubusercontent.com/Whonix/security-misc/master/etc/default/grub.d/40_enable_iommu.cfg >> /mnt/etc/grub.d/40_enable_iommu

# Setting GRUB configuration file permissions
chmod 755 /mnt/etc/grub.d/*

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

# Disable Connectivity Check.
bash -c 'cat > /mnt/etc/NetworkManager/conf.d/20-connectivity.conf' <<-'EOF'
[connectivity]
uri=http://www.archlinux.org/check_network_status.txt
interval=0
EOF

chmod 600 /mnt/etc/NetworkManager/conf.d/20-connectivity.conf

# Enable IPv6 privacy extensions
bash -c 'cat > /mnt/etc/NetworkManager/conf.d/ip6-privacy.conf' <<-'EOF'
[connection]
ipv6.ip6-privacy=2
EOF

chmod 600 /mnt/etc/NetworkManager/conf.d/ip6-privacy.conf

echo -ne "
-------------------------------------------------------------------------
                      Configuring the system
-------------------------------------------------------------------------
"

# Configuring the system.
arch-chroot /mnt /bin/bash -e <<EOF

    # Setting up timezone
    ln -sf /usr/share/zoneinfo/$time_zone /etc/localtime &>/dev/null
    
    # Setting up clock
    hwclock --systohc
       
    # Generating locales.my keys aren't even on
    echo "Generating locales."
    locale-gen &>/dev/null

    echo -ne "
    -------------------------------------------------------------------------
                         Installing Pacman eye-candy features
    -------------------------------------------------------------------------
    "

    # Pacman eye-candy features
    sed -i 's/#Color/Color\nILoveCandy/' /etc/pacman.conf
    sed -i 's/#VerbosePkgLists/VerbosePkgLists/' /etc/pacman.conf
    sed -i 's/#ParallelDownloads = 5/ParallelDownloads = 5/' /etc/pacman.conf
    sed -i '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf
    pacman-key --recv-key FBA220DFC880C036 --keyserver keyserver.ubuntu.com
    pacman-key --lsign-key FBA220DFC880C036
    pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
    echo -e "\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist\n" >> /etc/pacman.conf
    #sed -i '1 s|^|Server = https://es-mirror.chaotic.cx/$repo/$arch\n\n|' /etc/pacman.d/chaotic-mirrorlist
    pacman -Syyu --noconfirm
    echo "Pacman eye-candy features installed."


    echo -ne "
    -------------------------------------------------------------------------
                         Installing GRUB on /efi
    -------------------------------------------------------------------------
    "
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
    grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB --modules="normal test efi_gop efi_uga search echo linux all_video gfxmenu gfxterm_background gfxterm_menu gfxterm loadenv configfile gzio part_gpt btrfs"
    
    # Creating grub config file.
    echo "Creating GRUB config file."
    grub-mkconfig -o /boot/grub/grub.cfg

    echo -ne "
    -------------------------------------------------------------------------
                        Setting root & user password
    -------------------------------------------------------------------------
    "
    
    # Giving wheel user sudo access
    echo -e "$root_password\n$root_password" | passwd root
    usermod -aG wheel root
    useradd -m -G wheel -s /bin/bash $username
    usermod -a -G wheel "$username" && mkdir -p /home/"$username" && chown "$username":wheel /home/"$username"
    echo -e "$password\n$password" | passwd $username
    groupadd -r audit
    gpasswd -a $username audit
    sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/g' /etc/sudoers
    echo "$username ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
    chown $username:$username /home/$username
      
    
    echo "/usr/lib/pipewire-0.3/jack" > /etc/ld.so.conf.d/pipewire-jack.conf

    echo -e "\n#GTK_USE_PORTAL=1\n" >> /etc/environment

    # Enabling audit service
    systemctl enable auditd &>/dev/null

    # Enabling auto-trimming service
    systemctl enable fstrim.timer &>/dev/null

    # Enabling NetworkManager
    echo "Enabling NetworkManager"
    systemctl enable NetworkManager &>/dev/null
    systemctl enable systemd-resolved &>/dev/null

    # Enabling SDDM
    echo "Enabling sddm"
    systemctl enable sddm &>/dev/null

    # Enabling Firewalld
    systemctl enable firewalld &>/dev/null
    echo "Enabled Firewalld."

    # Enabling systemd-oomd
    systemctl enable systemd-oomd &>/dev/null
    echo "Enabled systemd-oomd."

    # Enabling Snapper automatic snapshots    
    systemctl enable snapper-timeline.timer &>/dev/null
    systemctl enable snapper-cleanup.timer &>/dev/null
    systemctl enable grub-btrfs.path &>/dev/null
    echo "Enabled Snapper and automatic snapshots entries."

    # Setting umask to 077
    sed -i 's/022/077/g' /etc/profile
    echo "" >> /etc/bash.bashrc
    echo "umask 077" >> /etc/bash.bashrc
    echo "Setting umask to 077 - Done"

    sed -i 's/#MAKEFLAGS="-j2"/MAKEFLAGS="-j$(nproc)"/g; s/-)/--threads=0 -)/g; s/gzip/pigz/g; s/bzip2/pbzip2/g' /etc/makepkg.conf
    journalctl --vacuum-size=100M --vacuum-time=2weeks

    touch /etc/sysctl.d/99-swappiness.conf
    echo 'vm.swappiness=20' > /etc/sysctl.d/99-swappiness.conf

    echo "Set shutdown timeout"
    sed -i 's/.*DefaultTimeoutStopSec=.*$/DefaultTimeoutStopSec=5s/g' /etc/systemd/system.conf
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3"/g' /etc/default/grub
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="lsm=landlock,lockdown,yama,apparmor,bpf audit=1 nvidia-drm.modeset=1 /g' /etc/default/grub

    if lscpu -J | grep -q "Intel" >/dev/null 2>&1; then
        echo -e "Intel CPU was detected -> add intel_iommu=on"
        sed -i 's/^"GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="intel_iommu=on /g' /etc/default/grub
    elif lscpu -J | grep -q "AMD" >/dev/null 2>&1; then
        echo -e "AMD CPU was detected -> add amd_iommu=on"
        sed -i 's/^"GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="amd_iommu=on /g' /etc/default/grub
    fi

    grub-mkconfig -o /boot/grub/grub.cfg

    
    #echo -ne "
    #-------------------------------------------------------------------------
    #                        zsh configuration
    #-------------------------------------------------------------------------
    #"
    #
    #chsh -s /bin/zsh
    #echo -e "$password" | sudo -u $username chsh -s /bin/zsh
    #echo -e "autoload -Uz promptinit\npromptinit\nprompt adam2\nsource /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh\nsource /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh\nsource /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh\nsource /usr/share/doc/pkgfile/command-not-found.zsh\nautoload -Uz run-help\nalias help=run-help" | tee -a /home/$username/.zshrc | tee -a /etc/zsh/zshrc


    #Install paru
    echo -ne "
    -------------------------------------------------------------------------
                          Installing paru - aur helper
    -------------------------------------------------------------------------
    "
    cd /home/$username/
    sudo -u $username git clone https://aur.archlinux.org/paru-bin.git
    cd paru-bin/ || exit
    sudo -u $username makepkg --noconfirm -si
    cd "$HOME" || exit
    sudo -u $username paru --noconfirm -Syu
    sed -i '$ d' /etc/sudoers
    echo "paru installed."

    # Enabling Reflector timer
    systemctl enable reflector.timer &>/dev/null
    echo "Enabled Reflector."

    # Get rid of system beep
    rmmod pcspkr
	echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf
    
    # Installing CyberRe Grub theme
    echo -ne "
    -------------------------------------------------------------------------
                          Installing CyberRe Grub theme
    -------------------------------------------------------------------------
    "
    THEME_DIR=/boot/grub/themes
    THEME_NAME=CyberRe
    echo -e "Creating the theme directory..."
    mkdir -p /boot/grub/themes/CyberRe
    echo -e "Copying the theme..."
    git clone https://github.com/khaleeldtxi/archlinux-install-script
    cp -a archlinux-install-script/CyberRe/* /boot/grub/themes/CyberRe
    echo -e "Backing up Grub config..."
    cp -an /etc/default/grub /etc/default/grub.bak
    echo -e "Setting the theme as the default..."
    grep "GRUB_THEME=" /etc/default/grub 2>&1 >/dev/null && sed -i '/GRUB_THEME=/d' /etc/default/grub
    chown $username:$username /etc/default/grub
    echo -e "GRUB_THEME=\"/boot/grub/themes/CyberRe/theme.txt\"" >> /etc/default/grub
    echo -e "Updating grub..."
    sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
    echo "Regenerate Grub configuration"
    grub-mkconfig -o /boot/grub/grub.cfg
    echo -e "All set!"
    echo "CyberRe Grub theme installed."    

    echo "creating ~/.config/autostart - required to enable AppArmor notifications"
    mkdir -p -m 700 /home/${username}/.config/autostart &>/dev/null
    chown -R $username:$username /home/${username}/.config &>/dev/null
    chown -R $username:$username /home/${username}/.config/autostart &>/dev/null
    chmod 700 /home/${username}/.config/autostart &>/dev/null
    touch /home/${username}/.config/autostart/apparmor-notify.desktop
    echo "created ~/.config/autostart"
    
    # Enabling AppArmor
    echo "Enabling AppArmor."
    systemctl enable apparmor &>/dev/null
    systemctl enable auditd.service &>/dev/null
    sed -i 's/^log_group = root/log_group = audit/g' /etc/audit/auditd.conf
    echo "AppArmor enabled."

    echo "Enabling libvirtd service"
    systemctl enable libvirtd &>/dev/null
    usermod -G libvirt -a $username

EOF



# Enable AppArmor notifications
# Must create ~/.config/autostart first
echo -ne "
-------------------------------------------------------------------------
                     Enable AppArmor notifications
-------------------------------------------------------------------------
"
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


# bypass sudo password prompt
echo -e "root ALL=(ALL) NOPASSWD: ALL\n%wheel ALL=(ALL) NOPASSWD: ALL\n" > /mnt/etc/sudoers.d/00_nopasswd

# bypass polkit password prompt
cat >> /mnt/etc/polkit-1/rules.d/49-nopasswd_global.rules <<-'EOF'
/* Allow members of the wheel group to execute any actions
* without password authentication, similar to "sudo NOPASSWD:"
*/
polkit.addRule(function(action, subject) {
    if (subject.isInGroup("wheel")) {
        return polkit.Result.YES;
    }
});
EOF

cat >> /mnt/etc/polkit-1/rules.d/50-udisks.rules <<-'EOF'    
// Original rules: https://github.com/coldfix/udiskie/wiki/Permissions
// Changes: Added org.freedesktop.udisks2.filesystem-mount-system, as this is used by Dolphin.
polkit.addRule(function(action, subject) {
  var YES = polkit.Result.YES;
  // NOTE: there must be a comma at the end of each line except for the last:
  var permission = {
    // required for udisks1:
    "org.freedesktop.udisks.filesystem-mount": YES,
    "org.freedesktop.udisks.luks-unlock": YES,
    "org.freedesktop.udisks.drive-eject": YES,
    "org.freedesktop.udisks.drive-detach": YES,
    // required for udisks2:
    "org.freedesktop.udisks2.filesystem-mount": YES,
    "org.freedesktop.udisks2.encrypted-unlock": YES,
    "org.freedesktop.udisks2.eject-media": YES,
    "org.freedesktop.udisks2.power-off-drive": YES,
    // Dolphin specific
    "org.freedesktop.udisks2.filesystem-mount-system": YES,
    // required for udisks2 if using udiskie from another seat (e.g. systemd):
    "org.freedesktop.udisks2.filesystem-mount-other-seat": YES,
    "org.freedesktop.udisks2.filesystem-unmount-others": YES,
    "org.freedesktop.udisks2.encrypted-unlock-other-seat": YES,
    "org.freedesktop.udisks2.eject-media-other-seat": YES,
    "org.freedesktop.udisks2.power-off-drive-other-seat": YES
  };
  if (subject.isInGroup("storage")) {
    return permission[action.id];
  }
});
EOF

echo -e "\nDone.\n\n"

cd $pwd

# Finishing up
echo "Done, you may now wish to reboot. Further changes can be done by chrooting into mnt."

# Run following command after rebooting and installing kdeconnect
#sudo firewall-cmd --zone=home --add-service kdeconnect --permanent
#sudo systemctl enable --now virtlogd.socket
#sudo virsh net-start default
#sudo virsh net-autostart default
