#!/bin/bash
# build.sh


WORK_DIR=$(pwd)/work
OUTPUT_DIR=$(pwd)/output

OUTPUT_ROOTFS_DIR=$OUTPUT_DIR/rootfs
OUTPUT_UBOOT_DIR=$OUTPUT_DIR/uboot
OUTPUT_KERNEL_DIR=$OUTPUT_DIR/kernel
OUTPUT_IMAGE_DIR=$OUTPUT_DIR/images

BUILDROOT_DIR="$WORKDIR/buildroot"
UBOOT_DIR="$WORKDIR/u-boot"
LINUX_DIR="$WORKDIR/linux"

IMAGE_NAME="rpi5_bootable_image.img"


MOUNT_DIR="mnt"
ROOTFS_DIR="$OUTPUT_DIR/target"
KERNEL_DIR="$LINUX_DIR/arch/arm/boot"

UBOOT_BIN="$UBOOT_DIR/u-boot.bin"
BOOT_DIR="$MOUNT_DIR/boot"
ROOT_DIR="$MOUNT_DIR/rootfs"

IMAGE_FILE="sdcard.img"
IMAGE_SIZE=4G  
LOOP_DEV=""
MOUNT_DIR=$(mktemp -d)
CROSS_COMPILE="aarch64-linux-gnu-"




echo_success() { echo -e "\e[32m[SUCCESS]\e[0m $1"; }
echo_warning() { echo -e "\e[33m[WARNING]\e[0m $1"; }
echo_error() { echo -e "\e[31m[ERROR]\e[0m $1"; }
echo_info() { echo -e "\e[34m[INFO]\e[0m $1"; }


if [[ $EUID -ne 0 ]]; then
    echo_error "Dieses Skript muss als root ausgeführt werden!"
    exec sudo "$0" "$@"
fi



buildroot_menu() {
  choice=$(dialog --menu "Wähle eine Option für Buildroot" 15 50 4 \
    1 "Raspberry Pi 4" \
    2 "Raspberry Pi 5" \
    3 "Zurück" \
    4 "Beenden" \
    2>&1 >/dev/tty)

  case $choice in
    1)
      echo "Du hast Raspberry Pi 4 für Buildroot ausgewählt."
      make_buildroot raspberrypi4b_defconfig
      ;;
    2)
      echo "Du hast Raspberry Pi 5 für Buildroot ausgewählt."
      make_buildroot raspberrypi5_defconfig
      ;;
    3)
      return
      ;;
    4)
      exit 0
      ;;
    *)
      echo "Ungültige Option."
      ;;
  esac
}

kernel_menu() {
  choice=$(dialog --menu "Wähle eine Option für den Linux Kernel" 15 50 4 \
    1 "Raspberry Pi 4" \
    2 "Raspberry Pi 5" \
    3 "Zurück" \
    4 "Beenden" \
    2>&1 >/dev/tty)

  case $choice in
    1)
      echo "Du hast Raspberry Pi 4 für den Linux Kernel ausgewählt."
      make rpi_4_defconfig
      ;;
    2)
      echo "Du hast Raspberry Pi 5 für den Linux Kernel ausgewählt."
      make_kernel bcm2712_defconfig
      ;;
    3)
      return
      ;;
    4)
      exit 0
      ;;
    *)
      echo "Ungültige Option."
      ;;
  esac
}

uboot_menu() {
  choice=$(dialog --menu "Wähle eine Option für U-Boot" 15 50 4 \
    1 "Raspberry Pi 4" \
    2 "Raspberry Pi 5" \
    3 "Zurück" \
    4 "Beenden" \
    2>&1 >/dev/tty)

  case $choice in
    1)
      echo "Du hast Raspberry Pi 4 für U-Boot ausgewählt."
      make_u_boot rpi_4_defconfig;
      ;;
    2)
      echo "Du hast Raspberry Pi 5 für U-Boot ausgewählt."
      make_u_boot rpi_arm64_defconfig
      ;;
    3)
      return
      ;;
    4)
      exit 0
      ;;
    *)
      echo "Ungültige Option."
      ;;
  esac
}

main_menu() {
  while true; do
    choice=$(dialog --menu "Hauptmenü" 15 50 5 \
      1 "Buildroot" \
      2 "Linux Kernel" \
      3 "U-Boot" \
      4 "Build Image" \
      5 "Beenden" \
      2>&1 >/dev/tty)

    case $choice in
      1)
        buildroot_menu
        ;;
      2)
        kernel_menu
        ;;
      3)
        uboot_menu
        ;;
      4)
        echo "Du hast 'Build Image' ausgewählt."
        make_image;
        ;;
      5)
        exit 0
        ;;
      *)
        echo "Ungültige Option."
        ;;
    esac
  done
}






make_buildroot() {
    if [ -z "$1" ]; then
        echo_error "Fehler: Keine Konfiguration angegeben!"
        echo_info "Verwendung: buildroot <config_name>"
        exit 1
    fi

    CONFIG_NAME=$1 

    echo_info "Erstelle Root-Dateisystem mit Buildroot..."
    if [ ! -d "$BUILDROOT_DIR"]; then
        git clone https://github.com/raspberry-pi-firmware-building-org/buildroot "$BUILDROOT_DIR"
    fi

    cd $BUILDROOT_DIR

    if [ ! -f ".config" ]; then
        make $CONFIG_NAME 
    fi

    make
}

make_u_boot() {
    if [ -z "$1" ]; then
        echo_error "Fehler: Keine Konfiguration angegeben!"
        echo_info "Verwendung: make_u_boot <config_name>"
        exit 1
    fi

    CONFIG_NAME=$1  

    echo_info "Step 2: Building U-Boot mit Konfiguration $CONFIG_NAME..."
    if [ ! -d "$UBOOT_DIR" ]; then
        git clone https://source.denx.de/u-boot/u-boot.git "$UBOOT_DIR"
    fi

    cd $UBOOT_DIR

    make $CONFIG_NAME  

    make

    if [ ! -f "u-boot.bin" ] || [ ! -f "u-boot.img" ]; then
        echo "Fehler: U-Boot konnte nicht erfolgreich kompiliert werden!"
        exit 1
    fi

    cp u-boot.bin "$OUTPUT_DIR/"
    cp u-boot.img "$OUTPUT_DIR/"
    cp -r board/raspberrypi "$OUTPUT_DIR/"  

    echo "✅ U-Boot erfolgreich kompiliert und nach $OUTPUT_DIR verschoben!"
    cd -
}

make_kernel() {
    if [ -z "$1" ]; then
        echo_error "Fehler: Keine Konfiguration angegeben!"
        echo_info "Verwendung: make_u_boot <config_name>"
        exit 1
    fi

    CONFIG_NAME=$1  

    echo_info "[2/9] Baue den Linux-Kernel für Raspberry Pi 5..."

    cd $LINUX_DIR
    
    make $CONFIG_NAME  

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

    main_menu;

    # make_u_boot;
    # make_kernel;
    # make_rootfs;
    # make_image;
}

initialize;