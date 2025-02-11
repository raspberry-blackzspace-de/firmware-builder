# Buildroot Raspberry Pi 5 Image Builder

Dieses Skript erstellt ein bootfähiges Image für den Raspberry Pi 5 basierend auf **Buildroot**, **U-Boot** und dem **Linux-Kernel**.

## Voraussetzungen

### Erforderliche Pakete
Stelle sicher, dass folgende Pakete installiert sind:
```sh
sudo apt update && sudo apt install -y git build-essential bc bison flex libssl-dev libncurses5-dev qemu-user-static debootstrap parted u-boot-tools
```

### Repositories klonen
Lade die benötigten Repositories herunter:
```sh
git clone https://github.com/raspberry-pi-firmware-building-org/buildroot.git
cd buildroot
git checkout rpi5
cd ..

git clone https://github.com/raspberry-pi-firmware-building-org/u-boot.git
cd u-boot
git checkout rpi5
cd ..

git clone https://github.com/raspberry-pi-firmware-building-org/linux.git
cd linux
git checkout rpi5
cd ..
```

## Skript ausführen

### Erstellen des Images
Führe das Skript mit Root-Rechten aus:
```sh
sudo ./build.sh
```

Das Skript durchläuft folgende Schritte:
1. **U-Boot kompilieren**: Erstellt den Bootloader für den Raspberry Pi 5.
2. **Linux-Kernel kompilieren**: Erstellt den Kernel und die Gerätebaum-Dateien.
3. **Buildroot Root-Dateisystem generieren**: Erstellt ein RootFS mit Buildroot.
4. **Image erstellen & partitionieren**: Erstellt eine 4GB große Datei mit zwei Partitionen (FAT32 für Boot, ext4 für RootFS).
5. **Boot-Dateien kopieren**: Platziert Kernel, U-Boot und DTBs in die Boot-Partition.
6. **Root-Dateisystem einfügen**: Entpackt das generierte RootFS in die Root-Partition.
7. **Pakete im chroot installieren**: Falls nötig, können zusätzliche Pakete installiert werden.
8. **Finalisierung**: Bereinigt das System und trennt das Loop-Device.

### Image auf SD-Karte schreiben
Nach der erfolgreichen Erstellung des Images kann es auf eine SD-Karte geschrieben werden:
```sh
sudo dd if=sdcard.img of=/dev/sdX bs=4M status=progress && sync
```
⚠️ **Ersetze `/dev/sdX` mit dem korrekten Gerätenamen deiner SD-Karte!**

## Anpassungen
- Falls zusätzliche Pakete benötigt werden, können sie im `chroot`-Schritt des Skripts installiert werden.
- Das Root-Dateisystem kann mit einem eigenen Buildroot-Config angepasst werden.

## Fehlerbehebung
- Stelle sicher, dass alle benötigten Pakete installiert sind.
- Prüfe, ob genug Speicherplatz für das Image verfügbar ist.
- Falls das System nicht bootet, überprüfe die Boot-Partition auf korrekte U-Boot- und Kernel-Dateien.

## Lizenz
Dieses Projekt steht unter der MIT-Lizenz.

---
🚀 Viel Erfolg beim Erstellen deines eigenen Raspberry Pi 5 Images!




# Config
```sh

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

```


# U-Boot

```sh


git clone https://source.denx.de/u-boot/u-boot.git
cd u-boot
make rpi_5_defconfig
make -j$(nproc)
# Notwendige Dateien in den Zielordner verschieben
cp u-boot.bin "$OUTPUT_DIR/"
cp u-boot.img "$OUTPUT_DIR/"
cp -r board/raspberrypi "$OUTPUT_DIR/"  # Falls weitere Bootdateien benötigt werden
```

# Kernel

```sh
git clone https://github.com/raspberry-pi-firmware-building-org/linux.git
cd $LINUX_DIR
make bcm2712_defconfig   # BCM2712 ist der Chip des RPi 5
make -j$(nproc) Image dtbs modules
if [ ! -f "arch/arm64/boot/Image" ]; then
    echo_error "Fehler: Linux-Kernel Image wurde nicht erstellt!"
    exit 1
fi
mkdir -p $OUTPUT_DIR/kernel
sudo cp $LINUX_DIR/arch/arm64/boot/Image $OUTPUT_DIR/kernel
sudo cp $LINUX_DIR/arch/arm64/boot/dts/broadcom/*.dtb $OUTPUT_DIR/kernel
```

# Rootfs

```sh
cd $BUILDROOT_DIR
make clean
make raspberrypi5_defconfig
make -j$(nproc)
```