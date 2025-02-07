#!/bin/bash

# Variablen für die Verzeichnisse
BUILDROOT_DIR="buildroot"
UBOOT_DIR="u-boot"
LINUX_DIR="linux"
OUTPUT_DIR="output"
IMAGE_NAME="rpi5_bootable_image.img"
MOUNT_DIR="mnt"
ROOTFS_DIR="$OUTPUT_DIR/target"
KERNEL_DIR="$LINUX_DIR/arch/arm/boot"
UBOOT_BIN="$UBOOT_DIR/u-boot.bin"
BOOT_DIR="$MOUNT_DIR/boot"
ROOT_DIR="$MOUNT_DIR/rootfs"


# Farben für die Ausgabe
echo_success() { echo -e "\e[32m[SUCCESS]\e[0m $1"; }
echo_warning() { echo -e "\e[33m[WARNING]\e[0m $1"; }
echo_error() { echo -e "\e[31m[ERROR]\e[0m $1"; }
echo_info() { echo -e "\e[34m[INFO]\e[0m $1"; }

# Prüfe Root-Rechte
if [[ $EUID -ne 0 ]]; then
    echo_error "Dieses Skript muss als root ausgeführt werden!"
    exec sudo "$0" "$@"
fi

buildroot() {
    # Step 1: Buildroot
    echo_info "Erstelle Root-Dateisystem mit Buildroot..."
    if [ ! -d "$BUILDROOT_DIR"]; then
        git clone https://github.com/raspberry-pi-firmware-building-org/buildroot "$BUILDROOT_DIR"
    fi
    cd $BUILDROOT_DIR
    # Wenn noch keine Konfiguration vorhanden ist, auf die Standardkonfiguration setzen
    if [ ! -f ".config" ]; then
        make raspberrypi5_defconfig
    fi
    # Build starten
    make
}


u_boot() {
    # Step 2: U-Boot
    echo "Step 2: Building U-Boot..."
    if [ ! -d "$UBOOT_DIR" ]; then
        git clone https://source.denx.de/u-boot/u-boot.git "$UBOOT_DIR"
    fi
    cd $UBOOT_DIR
    # U-Boot für Raspberry Pi 5 konfigurieren
    make rpi_5_defconfig
    # U-Boot bauen
    make
}

linux_kernel() {
    # Step 3: Linux Kernel
    echo_info "[2/9] Baue den Linux-Kernel für Raspberry Pi 5..."
    if [ ! -d "$LINUX"]; then
        git clone https://github.com/raspberry-pi-firmware-building-org/linux "$LINUX"
    fi
    cd $LINUX
    # Kernel für Raspberry Pi 5 konfigurieren
    make bcm2711_defconfig
    # Kernel bauen
    make
}

make_image() {
    # Step 4: Erstellen eines Boot-Images (.img)
    echo "Step 4: Creating bootable .img..."

    # Erstelle ein leeres Image mit 1 GB Größe
    dd if=/dev/zero of=$IMAGE_NAME bs=1M count=1024

    # Partitionstabelle erstellen (2 Partitionen)
    fdisk $IMAGE_NAME <<EOF
    o
    n
    p
    1
    2048
    +256M
    n
    p
    2
    2048
    +500M
    w
EOF

    # Loop-Device für das Image erstellen
    LOOP_DEV=$(losetup -f --show $IMAGE_NAME)
    PART1="${LOOP_DEV}p1"
    PART2="${LOOP_DEV}p2"

    # Partitionen formatieren
    mkfs.vfat $PART1
    mkfs.ext4 $PART2

    # Partitionen mounten
    mkdir -p $MOUNT_DIR
    mount $PART1 $BOOT_DIR
    mount $PART2 $ROOT_DIR

    # Step 5: Dateien kopieren
    echo "Step 5: Copying files to image..."

    # U-Boot-Bootloader kopieren
    cp $UBOOT_BIN $BOOT_DIR/

    # Kernel (zImage) kopieren
    cp $KERNEL_DIR/zImage $BOOT_DIR/kernel.img

    # Root-Dateisystem von Buildroot kopieren
    cp -r $ROOTFS_DIR/* $ROOT_DIR/

    # Optionale Boot-Dateien (config.txt, cmdline.txt) hinzufügen, falls benötigt
    # cp config.txt $BOOT_DIR/
    # cp cmdline.txt $BOOT_DIR/

    # Step 6: Aufräumen
    echo "Step 6: Cleaning up..."

    # Partitionen aushängen
    umount $BOOT_DIR
    umount $ROOT_DIR

    # Loop-Gerät abmelden
    losetup -d $LOOP_DEV

    # Fertig
    echo "Das bootfähige Image wurde erfolgreich erstellt: $IMAGE_NAME"
}

initialize() {
    buildroot;
    u_boot;
    linux_kernel;
    make_image;
}

initialize;