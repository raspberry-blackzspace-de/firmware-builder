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


make_buildroot() {
    # Step 1: Buildroot
    echo "Step 1: Building Buildroot..."
    cd $BUILDROOT_DIR

    # Wenn noch keine Konfiguration vorhanden ist, auf die Standardkonfiguration setzen
    if [ ! -f ".config" ]; then
        make raspberrypi5_defconfig
    fi

    # Build starten
    make
}

make_uboot() {
    # Step 2: U-Boot
    echo "Step 2: Building U-Boot..."
    cd $UBOOT_DIR

    # U-Boot für Raspberry Pi 5 konfigurieren
    make rpi_5_defconfig

    # U-Boot bauen
    make
}

make_kernel() {
# Step 3: Linux Kernel
echo "Step 3: Building Linux Kernel..."
cd $LINUX_DIR

# Kernel für Raspberry Pi 5 konfigurieren
make bcm2711_defconfig

# Kernel bauen
make
}



create_partition() {
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
}

make_image() {
    # Step 4: Erstellen eines Boot-Images (.img)
    echo "Step 4: Creating bootable .img..."

    echo "Creating empty Images with 1GB!"
    # Erstelle ein leeres Image mit 1 GB Größe
    dd if=/dev/zero of=$IMAGE_NAME bs=1M count=1024

    # Partitionstabelle erstellen (2 Partitionen)
    echo "Creating partition table!"
    create_partition;

    # Loop-Device für das Image erstellen
    echo "Creating Loop-Device for image!"
    LOOP_DEV=$(losetup -f --show $IMAGE_NAME)
    PART1="${LOOP_DEV}p1"
    PART2="${LOOP_DEV}p2"

    echo "Format Partitions!"
    # Partitionen formatieren
    mkfs.vfat $PART1
    mkfs.ext4 $PART2

    echo "Mounting Partitions!!!"
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
    echo "Unmounting Partitons!"
    umount $BOOT_DIR
    umount $ROOT_DIR
    echo "Logout Loop Dev!"
    # Loop-Gerät abmelden
    losetup -d $LOOP_DEV

    # Fertig
    echo "Das bootfähige Image wurde erfolgreich erstellt: $IMAGE_NAME"
}