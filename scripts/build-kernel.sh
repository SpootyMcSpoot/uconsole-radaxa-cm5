#!/bin/bash
#
# Build kernel for Radxa CM5 uConsole
#
# Usage: ./build-kernel.sh <kernel_version>
#
# Environment variables:
#   KERNEL_REPO: Git repository URL (default: ak-rex/ClockworkRadxa-linux)
#   KERNEL_BRANCH: Git branch (default: linux-6.1-stan-rkr4.1)
#   OVERLAYS_REPO: Overlays repository (default: dev-null2019/radxa-cm5-uconsole)
#   ARCH: Target architecture (default: arm64)
#   CROSS_COMPILE: Cross-compiler prefix (default: aarch64-none-linux-gnu-)

set -e  # Exit on error
set -u  # Exit on undefined variable

# Configuration
KERNEL_VERSION="${1:-1}"
KERNEL_REPO="${KERNEL_REPO:-https://github.com/ak-rex/ClockworkRadxa-linux.git}"
KERNEL_BRANCH="${KERNEL_BRANCH:-linux-6.1-stan-rkr4.1}"
OVERLAYS_REPO="${OVERLAYS_REPO:-https://github.com/dev-null2019/radxa-cm5-uconsole.git}"
ARCH="${ARCH:-arm64}"
CROSS_COMPILE="${CROSS_COMPILE:-aarch64-none-linux-gnu-}"

WORK_DIR="$(pwd)/build"
KERNEL_DIR="${WORK_DIR}/kernel"
OVERLAYS_DIR="${WORK_DIR}/overlays"
OUTPUT_DIR="${WORK_DIR}/output"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Create directories
mkdir -p "${WORK_DIR}"
mkdir -p "${OUTPUT_DIR}/kernel-packages"
mkdir -p "${OUTPUT_DIR}/overlays"

# Clone kernel if not exists
if [ ! -d "${KERNEL_DIR}" ]; then
    log_info "Cloning kernel repository..."
    git clone --depth=1 --branch="${KERNEL_BRANCH}" "${KERNEL_REPO}" "${KERNEL_DIR}"
else
    log_info "Using existing kernel directory"
fi

# Clone overlays if not exists
if [ ! -d "${OVERLAYS_DIR}" ]; then
    log_info "Cloning overlays repository..."
    git clone --depth=1 "${OVERLAYS_REPO}" "${OVERLAYS_DIR}"
else
    log_info "Using existing overlays directory"
fi

# Build kernel
log_info "Configuring kernel..."
"$(dirname "$0")/install-cwu50-new-panel-driver.sh" "${KERNEL_DIR}"
cd "${KERNEL_DIR}"
export ARCH
export CROSS_COMPILE
make rockchip_linux_defconfig

log_info "Building kernel (this will take 30-45 minutes)..."
make -j"$(nproc)" Image modules dtbs

log_info "Building kernel packages..."
export KDEB_PKGVERSION="${KERNEL_VERSION}"
make -j"$(nproc)" bindeb-pkg

# Move packages
log_info "Collecting kernel packages..."
mv ../*.deb "${OUTPUT_DIR}/kernel-packages/" 2>/dev/null || true

# Build overlays
log_info "Building device tree overlays..."
cd "${OVERLAYS_DIR}"
mkdir -p compiled_overlays

if [ -d "devicetree_overlays" ]; then
    KERNEL_INCLUDE="${KERNEL_DIR}/include"

    for dts in devicetree_overlays/*.dts; do
        [ -f "$dts" ] || continue
        basename=$(basename "$dts" .dts)
        log_info "Compiling overlay: ${basename}"

        gcc -E -nostdinc -I"${KERNEL_INCLUDE}" -I"devicetree_overlays" \
            -undef -D__DTS__ -x assembler-with-cpp "$dts" | \
            dtc -@ -I dts -O dtb -o "compiled_overlays/${basename}.dtbo" -
    done

    cp compiled_overlays/*.dtbo "${OUTPUT_DIR}/overlays/"
fi

log_info "Kernel build complete!"
log_info "Kernel packages: ${OUTPUT_DIR}/kernel-packages/"
log_info "Overlays: ${OUTPUT_DIR}/overlays/"
