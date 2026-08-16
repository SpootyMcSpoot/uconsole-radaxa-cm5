# Build Scripts

These scripts allow you to build Radxa CM5 uConsole images locally without using GitHub Actions.

## Prerequisites

### For Kernel Build
- Cross-compiler toolchain (aarch64)
- Build tools: `build-essential`, `bc`, `bison`, `flex`, `libssl-dev`, `libncurses5-dev`, `device-tree-compiler`

Install on Ubuntu/Debian:
```bash
sudo apt-get install build-essential bc bison flex libssl-dev libncurses5-dev \
    device-tree-compiler u-boot-tools dwarves git wget xz-utils kmod cpio

# Install ARM cross-compiler
wget https://developer.arm.com/-/media/Files/downloads/gnu/12.2.rel1/binrel/arm-gnu-toolchain-12.2.rel1-x86_64-aarch64-none-linux-gnu.tar.xz
sudo tar -xf arm-gnu-toolchain-12.2.rel1-x86_64-aarch64-none-linux-gnu.tar.xz -C /opt/
export PATH="/opt/arm-gnu-toolchain-12.2.rel1-x86_64-aarch64-none-linux-gnu/bin:$PATH"
```

### For Image Build
- Root access (sudo)
- Image tools: `wget`, `xz`, `kmod`, `cpio`, `rsync`, `dosfstools`, `parted`, `qemu-user-static`, `losetup`

Install on Ubuntu/Debian:
```bash
sudo apt-get install wget xz-utils kmod cpio rsync dosfstools parted \
    qemu-user-static binfmt-support pixz
```

## Usage

### End-to-end repeatable deployment

Fetch and cache a passed CI image. Repeated calls reuse verified local bytes:

```bash
scripts/fetch-uconsole-image.sh --run-id 31854866795 \
  --output-dir /var/home/pestilence/uconsole-staging/run-31854866795
```

The fetch helper also downloads Radxa's pinned
`rk3588_spl_loader_v1.15.113.bin` and verifies SHA-256
`26baab70e6b915364f7d73d88298366db1bfc346e34683e95d3d11b52492047f`.

One command drives flash, post-reboot provisioning, optional NVMe `/content` storage,
and validation. It waits automatically; only turning the physical Maskrom
switch off and power-cycling after flash cannot be automated:

```bash
SSHPASS='<ssh-password>' SUDO_PASSWORD='<sudo-password>' \
  scripts/deploy-uconsole.sh \
  --image radxa-cm5-uconsole_debian_bookworm.img \
  --loader /var/home/pestilence/uconsole-staging/run-31854866795/rk3588_spl_loader_v1.15.113.bin \
  --sha256 <published-raw-image-sha256> \
  --host 192.168.0.146 \
  --shtf-deb /path/to/shtf-box_arm64.deb

# Add only after the expected 2 TB device appears as /dev/nvme0n1:
#   --nvme-storage /dev/nvme0n1
```

Build/download raw Debian image, then flash one CM5 connected in Maskrom mode:

```bash
sudo scripts/flash-uconsole-maskrom.sh \
  --image radxa-cm5-uconsole_debian_bookworm.img \
  --loader /var/home/pestilence/uconsole-staging/run-31854866795/rk3588_spl_loader_v1.15.113.bin \
  --sha256 <published-raw-image-sha256>
```

Script requires exact RK3588 Maskrom USB identity, flashes eMMC, performs full
image-sized readback verification, and reboots. Turn Maskrom switch off for
normal boot.

After network boot, validate or idempotently reprovision target over SSH:

```bash
SSHPASS='<ssh-password>' SUDO_PASSWORD='<sudo-password>' \
  scripts/provision-uconsole-over-ssh.sh --host 192.168.0.146

# Only when the verified 2 TB NVMe appears; destructive to that NVMe only.
# eMMC remains the OS/root drive and NVMe becomes /content:
SSHPASS='<ssh-password>' SUDO_PASSWORD='<sudo-password>' \
  scripts/provision-uconsole-over-ssh.sh --host 192.168.0.146 \
  --nvme-storage /dev/nvme0n1

# Preserve an existing ext4 p1 instead of formatting it:
SSHPASS='<ssh-password>' SUDO_PASSWORD='<sudo-password>' \
  scripts/provision-uconsole-over-ssh.sh --host 192.168.0.146 \
  --adopt-nvme-storage /dev/nvme0n1
```

Remote automation rejects loopback and every address assigned to operator host,
then requires exact `Radxa CM5 RPI CM4 IO` device-tree identity. Target scripts
never execute locally. Built Debian image already includes HackerGadgets stack,
XFCE/LightDM, AIO2 boot rails, SHTF storage staging, NVMe bootstrap helper, and
hardware validator.

Samsung 990 PRO 2 TB users must update SSD firmware on a stable native M.2 PC
connection before initialization. The helper refuses firmware older than
`8B2QJXD7` and runs read-only probes at both ends of the device before its first
write. `smartd` stays disabled because older 990 PRO firmware can hang on NVMe
Identify; `smartmontools` remains installed for manual diagnostics.

When firmware cannot yet be updated, existing-filesystem adoption supports an
explicit `--allow-legacy-990-pro-firmware` override. It never permits formatting,
requires boundary reads plus a 512 MiB direct filesystem write/read test, and
aborts if kernel NVMe failure signatures appear. Use only with stable external
power and both charged 18650 cells installed. Successful setup keeps eMMC as
root, mounts NVMe at `/content`, and makes `shtf-box.service` require that mount.

For live kernel updates, install only `linux-image-*.deb`. CI-generated headers
contain cross-build helper binaries and are intended for build inspection, not
on-device DKMS compilation.

Kernel builds expose opt-in `nvme.mrrs=<bytes>` for controlled PCIe diagnostics.
It defaults to zero and does not alter normal behavior. A live Samsung 990 PRO
test confirmed `nvme.mrrs=128` in sysfs and PCI config, but the controller still
dropped on the same backup-GPT read; do not persist this parameter as a fix.

### 1. Build Kernel

```bash
# Build kernel with version suffix "1"
./scripts/build-kernel.sh 1

# Output:
#   build/output/kernel-packages/*.deb
#   build/output/overlays/*.dtbo
```

This will:
- Clone the kernel and overlay repositories
- Cross-compile the kernel
- Build Debian packages
- Compile device tree overlays

### 2. Build Image

```bash
# Build Debian image (requires sudo)
sudo ./scripts/build-image.sh debian 1

# Build Kali image
sudo ./scripts/build-image.sh kali 1

# Build RetroPie image
sudo ./scripts/build-image.sh retropie 1

# Output:
#   build/output/radxa-cm5-uconsole_<distro>_kernel-<version>_<date>.img.xz
#   build/output/radxa-cm5-uconsole_<distro>_kernel-<version>_<date>.img.xz.sha256
```

### Custom Base Image

You can provide a custom base image URL as the third argument:

```bash
sudo ./scripts/build-image.sh debian 1 "https://example.com/custom-image.img.xz"
```

## Environment Variables

### build-kernel.sh

- `KERNEL_REPO`: Git repository URL (default: `radxa/kernel`)
- `KERNEL_BRANCH`: Git ref (default: pinned `linux-6.1-stan-rkr5.1` commit)
- `OVERLAYS_REPO`: Overlays repository (default: `dev-null2019/radxa-cm5-uconsole`)
- `ARCH`: Target architecture (default: `arm64`)
- `CROSS_COMPILE`: Cross-compiler prefix (default: `aarch64-none-linux-gnu-`)

Example:
```bash
export KERNEL_REPO="https://github.com/my-fork/kernel.git"
export KERNEL_BRANCH="my-custom-branch"
./scripts/build-kernel.sh 1
```

## CI Script

The `build-kernel-ci.sh` script is used by GitHub Actions and assumes the kernel and overlay repositories are already cloned in the `build/` directory.

## Troubleshooting

### Kernel build fails
- Ensure cross-compiler is in PATH
- Check that all build dependencies are installed
- Verify you have enough disk space (kernel build requires ~15GB)

### Image build fails
- Must run as root (use `sudo`)
- Ensure kernel packages exist from previous build step
- Check for available loop devices: `losetup -f`
- Verify you have enough disk space (image build requires ~10GB)

### Loop device issues
If you get "loop device not found" errors:
```bash
# Check available loop devices
losetup -a

# Detach hung loop devices
sudo losetup -D
```

## Build Times

- Kernel build: 30-45 minutes (parallel compilation)
- Image build: 20-30 minutes per distro
- Total (kernel + 1 image): ~50-75 minutes

## Output Structure

```
build/
├── kernel/              # Cloned kernel source
├── overlays/            # Cloned overlay source
└── output/
    ├── kernel-packages/ # .deb files
    ├── overlays/        # .dtbo files
    ├── *.img.xz         # Compressed images
    └── *.img.xz.sha256  # Checksums
```
