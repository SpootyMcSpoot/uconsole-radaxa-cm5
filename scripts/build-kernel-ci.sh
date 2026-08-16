#!/bin/bash
#
# Build kernel for CI (assumes kernel and overlays already cloned)
#
# Usage: Called by GitHub Actions workflow
#
# Environment variables (must be set):
#   ARCH: Target architecture
#   CROSS_COMPILE: Cross-compiler prefix
#   KERNEL_VERSION: Kernel version suffix

set -e
set -u

KERNEL_DIR="build/kernel"
OVERLAYS_DIR="build/overlays"
OUTPUT_DIR="build/output"

echo "Building kernel..."
./scripts/install-cwu50-new-panel-driver.sh "${KERNEL_DIR}"
git -C "${KERNEL_DIR}" apply --check ../../patches/nvme-pci-mrrs-parameter.patch
git -C "${KERNEL_DIR}" apply ../../patches/nvme-pci-mrrs-parameter.patch
cd "${KERNEL_DIR}"
make rockchip_linux_defconfig

# HackerGadgets Radxa CM5 adapter: NVMe root plus MT7921AUN USB Wi-Fi/BT.
# Force modules here because the vendor defconfig has varied across releases.
./scripts/config --enable CONFIG_PCI
./scripts/config --enable CONFIG_PCIEPORTBUS
./scripts/config --enable CONFIG_PCIE_ROCKCHIP
./scripts/config --enable CONFIG_PCIE_ROCKCHIP_HOST
./scripts/config --enable CONFIG_NVME_CORE
./scripts/config --enable CONFIG_BLK_DEV_NVME
./scripts/config --module CONFIG_MT76
./scripts/config --module CONFIG_MT76_USB
./scripts/config --module CONFIG_MT792x_LIB
./scripts/config --module CONFIG_MT7921_COMMON
./scripts/config --module CONFIG_MT7921U
./scripts/config --module CONFIG_BT_HCIBTUSB
./scripts/config --enable CONFIG_BT_HCIBTUSB_MTK
./scripts/config --module CONFIG_DRM_PANEL_CWU50
./scripts/config --module CONFIG_BACKLIGHT_OCP8178
./scripts/config --enable CONFIG_NEW_LEDS
./scripts/config --enable CONFIG_LEDS_CLASS
./scripts/config --enable CONFIG_LEDS_GPIO
make olddefconfig

for symbol in BLK_DEV_NVME MT7921U BT_HCIBTUSB DRM_PANEL_CWU50 BACKLIGHT_OCP8178 LEDS_GPIO; do
    grep -Eq "^CONFIG_${symbol}=(y|m)$" .config || {
        echo "Required kernel symbol CONFIG_${symbol} missing" >&2
        exit 1
    }
done
grep -q 'cwu50_init_sequence2' drivers/gpu/drm/panel/panel-cwu50.c
grep -q 'is_new_panel' drivers/gpu/drm/panel/panel-cwu50.c
grep -q 'GPIO panel ID is authoritative on RK3588' drivers/gpu/drm/panel/panel-cwu50.c
grep -q 'PCIe MRRS limited to %d bytes' drivers/nvme/host/pci.c
make -j"$(nproc)" Image modules dtbs

echo "Building kernel packages..."
export KDEB_PKGVERSION="${KERNEL_VERSION}"
make -j"$(nproc)" bindeb-pkg

echo "Collecting kernel packages..."
mkdir -p "../../${OUTPUT_DIR}/kernel-packages"
mv ../*.deb "../../${OUTPUT_DIR}/kernel-packages/"

echo "Building device tree overlays..."
cd "../../${OVERLAYS_DIR}"
mkdir -p compiled_overlays
mkdir -p "../output/overlays"

if [ -d "devicetree_overlays" ]; then
    KERNEL_INCLUDE="../../${KERNEL_DIR}/include"

    for dts in devicetree_overlays/*.dts; do
        [ -f "$dts" ] || continue
        basename=$(basename "$dts" .dts)
        echo "  Compiling: ${basename}"

        gcc -E -nostdinc -I"${KERNEL_INCLUDE}" -I"devicetree_overlays" \
            -undef -D__DTS__ -x assembler-with-cpp "$dts" | \
            dtc -@ -I dts -O dtb -o "compiled_overlays/${basename}.dtbo" -
    done

    cp compiled_overlays/*.dtbo "../output/overlays/"
fi

echo "Kernel build complete!"
