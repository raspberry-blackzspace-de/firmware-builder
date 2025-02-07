# Linux Kernel - README

```md
# 1. Baue den Linux Kernel

```sh
git clone https://github.com/raspberry-pi-firmware-building-org/linux linux
cd linux
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- bcm2712_defconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
```

# Linux Kernel: Build - Skript

```sh
WORKDIR=$(pwd)/work
LINUX_DIR=$WORKDIR/linux
OUTPUT_DIR=$(pwd)/output/images

mkdir -p $WORKDIR
cd $WORKDIR
git clone https://github.com/raspberry-pi-firmware-building-org/linux linux
cd $LINUX_DIR
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- bcm2712_defconfig 
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)


mkdir -p $OUTPUT_DIR
cp arch/arm64/boot/Image $OUTPUT_DIR/kernel.img
cp arch/arm64/boot/dts/broadcom/*.dtb $OUTPUT_DIR
# Kopiere die System-Firmware und Bootloader-Dateien
cp -r /usr/lib/u-boot/rpi_5 $OUTPUT_DIR/bootloader/
# Kopiere die Konfigurationsdatei und initramfs
cp arch/arm64/boot/dts/overlays/*.dtb* $OUTPUT_DIR/boot/

```

# 2. Baue das RootFS
```sh
WORKDIR=$(pwd)/work
BUILDROOT_DIR=$WORKDIR/buildroot
ROOTFS_TAR="rootfs.tar"
ROOTFS_DIR="/mnt/rootfs"
OUTPUT_DIR=$(pwd)/output/rootfs

echo "[1/4] - Erstelle: '$WORKDIR' & '$OUTPUT_DIR' !!!... .. ."
mkdir -p $WORKDIR
mkdir -p $OUTPUT_DIR

cd $WORKDIR

echo "[2/4] - Klone: 'buildroot' Repository!!!... .. ."
git clone https://git.buildroot.net/buildroot.git

cd $BUILDROOT_DIR

echo "[3/4] - Konfiguriere RootFS mit Buildroot für das Raspberry Pi 5..."
make raspberrypi5_defconfig
# make raspberrypi4_defconfig # Für Raspberry Pi 4

echo "[4/4] - Baue RootFS mit Buildroot..."
make

```

# 3. Bilde U-BOOT 

```sh
git clone https://source.denx.de/u-boot/u-boot.git
cd u-boot
# make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- rpi_4_defconfig  # Raspberry Pi 4
# make rpi_arm64_defconfig

make rpi_5_defconfig
make -j$(nproc) CROSS_COMPILE=aarch64-linux-gnu-
cp u-boot.bin $OUTPUT_DIR
```