#!/bin/bash

set -e  # Stop on error

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

echo_success "Skript läuft mit Root-Rechten."

# Konfiguration
IMAGE_FILE="sdcard.img"
IMAGE_SIZE=4G  # Größe des Images für RPi 5 angepasst
LOOP_DEV=""
MOUNT_DIR=$(mktemp -d)
BUILDROOT_DIR=$(pwd)/buildroot
CROSS_COMPILE="aarch64-linux-gnu-"
UBOOT_DIR=$(pwd)/u-boot
LINUX_DIR=$(pwd)/linux
OUTPUT_DIR=$BUILDROOT_DIR/output/images



make_u_boot() {
    # Schritt 1: Baue U-Boot für Raspberry Pi 5
    echo_info "[1/9] Baue U-Boot für Raspberry Pi 5..."

    # U-Boot klonen, falls nicht vorhanden
    if [ ! -d "$UBOOT_DIR" ]; then
        git clone https://source.denx.de/u-boot/u-boot.git "$UBOOT_DIR"
    fi

    # Wechsle ins U-Boot-Verzeichnis
    cd $UBOOT_DIR

    # Konfiguration für den Raspberry Pi 5 setzen
    make rpi_5_defconfig

    # U-Boot kompilieren
    make -j$(nproc)

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

make_rootfs() {
    # Schritt 3: Erstelle Root-Dateisystem mit Buildroot
    echo_info "[3/9] Erstelle Root-Dateisystem mit Buildroot..."
    cd $BUILDROOT_DIR
    make clean
    make raspberrypi5_defconfig
    make -j$(nproc)
    cd -

    if [ ! -f "$OUTPUT_DIR/rootfs.tar" ]; then
        echo_error "Fehler: rootfs.tar wurde nicht gefunden! Stelle sicher, dass Buildroot richtig konfiguriert ist."
        exit 1
    fi
    echo_success "Root-Dateisystem wurde erfolgreich erstellt."
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