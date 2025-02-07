#!/bin/bash

set -e



# Variablen
WORKDIR=$(pwd)/work
BUILDROOT_DIR=$WORKDIR/buildroot
ROOTFS_TAR="rootfs.tar"
ROOTFS_DIR="/mnt/rootfs"
OUTPUT_DIR=$(pwd)/output/rootfs

BUILDROOT_DIR="$WORKDIR/buildroot"
UBOOT_DIR="$WORKDIR/u-boot"
LINUX_DIR="$WORKDIR/linux"

OUTPUT_DIR=$(pwd)/output

IMAGE_NAME="rpi5_bootable_image.img"

MOUNT_DIR="mnt"
ROOTFS_DIR="$OUTPUT_DIR/target"
KERNEL_DIR="$LINUX_DIR/arch/arm/boot"

UBOOT_BIN="$UBOOT_DIR/u-boot.bin"
BOOT_DIR="$MOUNT_DIR/boot"
ROOT_DIR="$MOUNT_DIR/rootfs"

IMAGE_FILE="sdcard.img"
IMAGE_SIZE=4G  # Größe des Images für RPi 5 angepasst
LOOP_DEV=""
MOUNT_DIR=$(mktemp -d)
CROSS_COMPILE="aarch64-linux-gnu-"

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



make_buildroot() {
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



make_u_boot() {
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

    # Prüfen, ob die benötigten Dateien erstellt wurden
    if [ ! -f "u-boot.bin" ] || [ ! -f "u-boot.img" ]; then
        echo "Fehler: U-Boot konnte nicht erfolgreich kompiliert werden!"
        exit 1
    fi

    # Notwendige Dateien in den Zielordner verschieben
    cp u-boot.bin "$OUTPUT_DIR/"
    cp u-boot.img "$OUTPUT_DIR/"
    cp -r board/raspberrypi "$OUTPUT_DIR/"  # Falls weitere Bootdateien benötigt werden

    echo "✅ U-Boot erfolgreich kompiliert und nach $OUTPUT_DIR verschoben!"
    cd -
}

make_kernel() {
    # Schritt 2: Baue den Linux-Kernel für Raspberry Pi 5
    echo_info "[2/9] Baue den Linux-Kernel für Raspberry Pi 5..."
    # CD Into Kernel Dir
    cd $LINUX_DIR
    # Configuring
    make bcm2712_defconfig  # BCM2712 ist der Chip des RPi 5
    make -j$(nproc) Image dtbs modules
    if [ ! -f "arch/arm64/boot/Image" ]; then
        echo_error "Fehler: Linux-Kernel Image wurde nicht erstellt!"
        exit 1
    fi
    echo_success "Linux-Kernel erfolgreich erstellt."
    cd -
}


make_image() {
    # Schritt 4: Erstelle ein leeres Image
    echo_info "[4/9] Erstelle leeres Image ($IMAGE_FILE)..."
    dd if=/dev/zero of=$IMAGE_FILE bs=1M count=$(echo $IMAGE_SIZE | sed 's/G//')000
    LOOP_DEV=$(sudo losetup --show -fP $IMAGE_FILE)

    # Schritt 5: Partitioniere das Image
    echo_info "[5/9] Partitioniere Image..."
    sudo parted -s $LOOP_DEV mklabel gpt
    sudo parted -s $LOOP_DEV mkpart primary fat32 1MiB 512MiB
    sudo parted -s $LOOP_DEV mkpart primary ext4 512MiB 100%
    sudo mkfs.vfat -F32 ${LOOP_DEV}p1
    sudo mkfs.ext4 ${LOOP_DEV}p2

    # Schritt 6: Dateien auf Boot-Partition kopieren
    echo_info "[6/9] Kopiere Boot-Dateien..."
    sudo mount ${LOOP_DEV}p1 $MOUNT_DIR
    sudo cp $LINUX_DIR/arch/arm64/boot/Image $MOUNT_DIR
    sudo cp $UBOOT_DIR/u-boot.bin $MOUNT_DIR
    sudo cp $LINUX_DIR/arch/arm64/boot/dts/broadcom/*.dtb $MOUNT_DIR
    sync
    sudo umount $MOUNT_DIR

    # Schritt 7: Root-Dateisystem kopieren
    echo_info "[7/9] Kopiere Root-Dateisystem..."
    sudo mount ${LOOP_DEV}p2 $MOUNT_DIR
    sudo tar -xpf $OUTPUT_DIR/rootfs.tar -C $MOUNT_DIR
    sync

    # Schritt 8: Pakete im chroot installieren
    echo_info "[8/9] Installiere Pakete im chroot..."
    sudo mount --bind /dev $MOUNT_DIR/dev
    sudo mount --bind /sys $MOUNT_DIR/sys
    sudo mount --bind /proc $MOUNT_DIR/proc
    sudo mount --bind /run $MOUNT_DIR/run

    echo_info "Wechsle in das chroot..."
    sudo chroot $MOUNT_DIR /bin/bash -c "apt update && apt install -y vim htop"

    echo_info "Unmount chroot-Umgebung..."
    sudo umount $MOUNT_DIR/dev $MOUNT_DIR/sys $MOUNT_DIR/proc $MOUNT_DIR/run
    sync
    sudo umount $MOUNT_DIR

    # Schritt 9: Image abschließen
    echo_info "[9/9] Bereinige und trenne Loop-Gerät..."
    sudo losetup -d $LOOP_DEV
    rm -rf $MOUNT_DIR

    echo_success "Fertig! Das bootfähige Image für Raspberry Pi 5 ist unter $IMAGE_FILE verfügbar."
    echo_info "Schreibe es auf eine SD-Karte mit: sudo dd if=$IMAGE_FILE of=/dev/sdX bs=4M status=progress && sync"
}



initialize() {
    make_u_boot;
    make_kernel;
    make_rootfs;
    make_image;
}

initialize;