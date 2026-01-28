#!/bin/bash
set -e

# Directories
ASSETS_DIR="assets/bin"
LINUX_DIR="$ASSETS_DIR/linux"
MACOS_DIR="$ASSETS_DIR/macos"

mkdir -p "$LINUX_DIR"
mkdir -p "$MACOS_DIR"

echo "Downloading dependencies..."

# --- UNRAR ---

# Linux x64
echo "Downloading Unrar for Linux..."
curl -L -o unrar_linux.tar.gz https://www.rarlab.com/rar/rarlinux-x64-701.tar.gz
tar -xzf unrar_linux.tar.gz
mv rar/unrar "$LINUX_DIR/"
rm -rf rar unrar_linux.tar.gz
chmod +x "$LINUX_DIR/unrar"

# macOS (Universal/x64)
echo "Downloading Unrar for macOS..."
curl -L -o unrar_macos.tar.gz https://www.rarlab.com/rar/rarmacos-x64-701.tar.gz
tar -xzf unrar_macos.tar.gz
mv rar/unrar "$MACOS_DIR/"
rm -rf rar unrar_macos.tar.gz
chmod +x "$MACOS_DIR/unrar"

# --- 7-Zip ---

# Linux x64
echo "Downloading 7-Zip for Linux..."
curl -L -o 7z_linux.tar.xz https://www.7-zip.org/a/7z2408-linux-x64.tar.xz
mkdir -p 7z_linux
tar -xf 7z_linux.tar.xz -C 7z_linux
mv 7z_linux/7zzs "$LINUX_DIR/7z" # using 7zzs (static) as 7z
rm -rf 7z_linux 7z_linux.tar.xz
chmod +x "$LINUX_DIR/7z"

# macOS
echo "Downloading 7-Zip for macOS..."
curl -L -o 7z_mac.tar.xz https://www.7-zip.org/a/7z2408-mac.tar.xz
mkdir -p 7z_mac
tar -xf 7z_mac.tar.xz -C 7z_mac
mv 7z_mac/7zz "$MACOS_DIR/7z" # macOS usually uses 7zz
rm -rf 7z_mac 7z_mac.tar.xz
chmod +x "$MACOS_DIR/7z"

echo "Dependencies downloaded successfully!"
ls -l "$LINUX_DIR"
ls -l "$MACOS_DIR"
