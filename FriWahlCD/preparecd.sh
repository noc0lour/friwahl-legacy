#!/bin/bash

INFO="\033[42;1m"
BLACK="\033[0m"

ROOTFS=work/airootfs

# NOTE: this requires the script to be executed from its very location
# WARNING: set the path so we get the correct version of mkarchiso; otherwise, the wrong architecture might be used
# you need to manually set the architecture (arch=i686) in ./archiso/archiso/mkarchiso, otherwise the image will be
# built with your machine's architecture, which might be wrong (x86_64 will cause problems with the live CDs)
export PATH=./archiso/archiso:$PATH

rm -rf work

sed "s|%ustarepo%|$(readlink -f usta/repo)|g" usta/data/pacman.conf > /tmp/pacman.conf

echo -e $INFO"Installiere Pakete..."$BLACK

mkarchiso -v -C /tmp/pacman.conf init
mkarchiso -v -C /tmp/pacman.conf -p base install
mkarchiso -v -C /tmp/pacman.conf -p syslinux install

mkarchiso -v -C /tmp/pacman.conf -p "openssh unzip zip irssi ipw2100-fw ipw2200-fw rfkill wireless_tools zd1211-firmware broadcom-wl b43-firmware wpa_supplicant openssl openvpn perl iptables dhcp dhclient fping curl perl-www-curl expect pygobject vim wavemon dialog-usta dnsutils" install || (echo "Fehler beim Installieren zusaetzlicher Pakete" && exit 1)
# TODO plymount, plymouth-theme-usta hinzufügen

#fehlende pakete: madwifi madwifi-utils

echo -e $INFO"Kopiere System Dateien..."$BLACK

rm -f $ROOTFS/etc/systemd/system/getty.target.wants/getty\@tty1.service

cp -a usta/sysfiles/* $ROOTFS
chown -R 1000:100 $ROOTFS/home/irc

echo -e $INFO"Generiere Locales..."$BLACK
mkarchiso -r "locale-gen" run

mkdir -p work/iso/arch/boot/i686

echo -e $INFO"Installiere ArchISO Hooks..."$BLACK
make -C archiso DESTDIR=$(readlink -f $ROOTFS) install-initcpio

echo -e $INFO"Erstelle Wahl-Splash..."$BLACK
cp $ROOTFS/etc/splash/usta/images/background.png /tmp
usta/scripts/splash.sh people.dat /tmp/background.png $ROOTFS/etc/splash/usta/images/background.png
rm /tmp/background.png

echo -e $INFO"Erstelle InitCPIO..."$BLACK
mkarchiso -r "mkinitcpio -k /boot/vmlinuz-linux -g /boot/archiso.img" run

echo -e $INFO"Installiere Kernel, InitCPIO und Bootloader..."$BLACK

mv $ROOTFS/boot/archiso.img work/iso/arch/boot/i686
mv $ROOTFS/boot/vmlinuz-linux work/iso/arch/boot/i686/vmlinuz

mkdir work/iso/arch/boot/syslinux

mkdir work/iso/isolinux

cp $ROOTFS/usr/lib/syslinux/bios/* work/iso/isolinux
cp usta/data/isolinux.cfg work/iso/isolinux/isolinux.cfg

cp usta/data/aitab work/iso/arch


