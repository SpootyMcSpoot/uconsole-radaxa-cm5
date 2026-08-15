# Radxa CM5 uConsole Image Builder

Automated GitHub Actions pipeline for building custom Radxa CM5 images for the ClockworkPi uConsole.

## Overview

This pipeline automates the complete build process:
1. Cross-compiles Radxa's RK3588 Linux kernel with pinned ClockworkPi support
2. Builds device tree overlays for uConsole hardware
3. Injects custom kernel and overlays into base Radxa image
4. Creates flashable `.img.xz` image ready for deployment

## Prerequisites

### GitHub Repository Setup

1. Fork or clone this repository to your GitHub account
2. Ensure GitHub Actions is enabled for the repository
3. The workflow uses only free GitHub-hosted runners (ubuntu-22.04)

### Source Repositories

The pipeline pulls from:
- **Kernel**: `radxa/kernel` (`linux-6.1-stan-rkr5.1`, pinned commit `f87fca6cefcb`)
- **uConsole support**: pinned AK-Rex panel/backlight patch plus the newer-panel CWU50 driver
- **Overlays**: `dev-null2019/radxa-cm5-uconsole`

## Usage

### Available Workflows

**Build Radxa CM5 uConsole Images** (`build-all-images.yml`)
- Single workflow with flexible build options
- Build kernel once, choose which image(s) to create
- Faster testing with single-distro builds
- Full multi-distro builds for releases

### Manual Build Trigger

1. **Fork this repository** to your GitHub account
2. Navigate to **Actions** tab in your fork: `https://github.com/YOUR_USERNAME/uconsole-radaxa-cm5/actions`
3. Select **Build Radxa CM5 uConsole Images**
4. Click **Run workflow**
5. Configure parameters:
   - **kernel_version**: Version suffix (default: `1`)
   - **build_target**: Select which image(s) to build
     - `debian` - Debian Bookworm only (recommended for testing)
     - `kali` - Kali Linux only
     - `retropie` - RetroPie only
     - `all` - All three distributions

### Build Parameters

```yaml
kernel_version: "1"    # Increment for each build (1, 2, 3...)
build_target: "debian" # debian, kali, retropie, or all
```

**Tip:** Use single-distro builds during development to save CI/CD minutes. Only build `all` for production releases.

### Local Builds

You can build images locally without GitHub Actions. See [scripts/README.md](scripts/README.md) for detailed instructions.

Quick start:
```bash
# Build kernel
./scripts/build-kernel.sh 1

# Build image (requires sudo)
sudo ./scripts/build-image.sh debian 1
```

## Build Process

### Stage 1: Environment Setup
- Installs ARM cross-compilation toolchain (GCC 12.2)
- Installs kernel build dependencies
- Installs image manipulation tools

### Stage 2: Kernel Compilation
- Clones the pinned Radxa kernel source and applies pinned ClockworkPi support
- Configures for Rockchip (RK3588S2) architecture
- Cross-compiles kernel, modules, and device trees
- Packages as Debian .deb files

### Stage 3: Overlay Compilation
- Clones uConsole overlay repository
- Compiles all `.dts` files to `.dtbo` format
- Prepares overlay installation

### Stage 4: Image Assembly
- Downloads base Radxa CM5 image
- Mounts image partitions
- Installs custom kernel packages via chroot
- Copies device tree overlays to boot partition
- Updates boot configuration
- Compresses final image with xz

### Stage 5: Validation & Upload
- Validates kernel packages exist
- Generates SHA256 checksum
- Uploads artifacts to GitHub Actions
- Creates release notes

## Artifacts

### Single Image Workflow

After successful build, the following artifacts are available for download:

### 1. `uconsole-image`
- **File**: `radxa-cm5-uconsole_bookworm_kernel-X_YYYYMMDD.img.xz`
- **Checksum**: `*.img.xz.sha256`
- **Size**: ~1-2 GB compressed
- **Retention**: 30 days

### 2. `kernel-packages`
- `linux-image-*.deb` - Kernel binary
- `linux-headers-*.deb` - Kernel headers
- `linux-libc-dev-*.deb` - Kernel libc development files
- **Retention**: 30 days

### 3. `device-tree-overlays`
- Compiled `.dtbo` files for uConsole hardware
- **Retention**: 30 days

### 4. `release-notes`
- Build metadata and installation instructions
- **Retention**: 30 days

### Multi-Distro Workflow

The all-images workflow produces 4 artifact sets:

### 1. `debian-image`
- Base Debian Bookworm CLI image
- Minimal system, ~1-2 GB compressed

### 2. `kali-image`
- Kali Linux with security tools
- Kali repos enabled, ~1-2 GB compressed
- Tools installed on-demand

### 3. `retropie-image`
- RetroPie gaming platform
- Setup script included, ~1-2 GB compressed
- Complete installation required on first boot

### 4. `kernel-build` (shared)
- Kernel packages used by all images
- Device tree overlays
- **Retention**: 1 day (intermediate artifact)

### 5. `release-notes`
- Multi-distro build summary
- Installation instructions for each distro

## Installation Instructions

### Flash Image to microSD Card

```bash
# Download the compressed image and checksum
wget <artifact-url>/radxa-cm5-uconsole_bookworm_kernel-X_YYYYMMDD.img.xz
wget <artifact-url>/radxa-cm5-uconsole_bookworm_kernel-X_YYYYMMDD.img.xz.sha256

# Verify integrity
sha256sum -c radxa-cm5-uconsole_bookworm_kernel-X_YYYYMMDD.img.xz.sha256

# Extract image
xz -d -v radxa-cm5-uconsole_bookworm_kernel-X_YYYYMMDD.img.xz

# Flash to microSD card (replace /dev/sdX with your device)
# WARNING: This will destroy all data on the target device
sudo dd if=radxa-cm5-uconsole_bookworm_kernel-X_YYYYMMDD.img \
        of=/dev/sdX \
        bs=4M \
        status=progress \
        conv=fsync

# Sync and eject
sync
sudo eject /dev/sdX
```

### Install Only Kernel Packages (Advanced)

If you already have a Radxa CM5 image and only want to update the kernel:

```bash
# On the running Radxa CM5 system
wget <artifact-url>/kernel-packages/*.deb
sudo dpkg -i linux-image-*.deb
sudo dpkg -i linux-headers-*.deb
sudo apt-get install -f
sudo update-initramfs -u -k all
sudo reboot
```

## Hardware Compatibility

### Tested Working
- ✅ Display (IPS LCD)
- ✅ Keyboard (I2C interface)
- ✅ USB ports (USB-A and USB-C)
- ✅ Power management (PMU)
- ✅ 4G LTE module
- ✅ microSD card reader

### Known Limitations
- ❌ **WiFi/Bluetooth**: Not available (hardware limitation - CM5 has no wireless)
- ⚠️ **Audio**: Mono only, experimental
- ⚠️ **HDMI**: Not available on standard uConsole carrier board
  - **Solution**: Use [uConsole Upgrade Kit adapter board](https://hackergadgets.com/products/pre-order-adapter-board-for-uconsole-ugrade-kit) for HDMI output
  - Adapter provides HDMI without modifying the uConsole

### Workarounds
- **WiFi**: Use USB WiFi dongle
- **Bluetooth**: Use USB Bluetooth adapter
- **Audio**: USB audio device recommended
- **HDMI**: Use uConsole upgrade adapter board (no hardware mod required)

## Customization

### Modify Kernel Configuration

To enable additional kernel modules or change configuration:

1. Edit `.github/workflows/build-uconsole-image.yml`
2. Add configuration commands in the "Configure kernel" step:

```yaml
- name: Configure kernel
  working-directory: kernel
  run: |
    export ARCH=arm64
    export CROSS_COMPILE=aarch64-none-linux-gnu-
    make rockchip_linux_defconfig
    
    # Enable custom modules
    ./scripts/config --enable CONFIG_MY_MODULE
    ./scripts/config --disable CONFIG_UNWANTED_FEATURE
    
    make olddefconfig
    make savedefconfig
```

### Add Custom Overlays

To include additional device tree overlays:

1. Add `.dts` files to the `overlays/devicetree_overlays/` directory
2. They will be automatically compiled during the build

### Change Base Image

To use a different base image:

1. When triggering the workflow, set `base_image_url` to your custom image URL
2. The image must be in `.img.xz` format
3. Partition layout should be compatible (boot + root partitions)

## Troubleshooting

### Build Fails: Out of Disk Space

GitHub runners have limited disk space. If the build fails:
- The workflow already removes unnecessary packages
- Consider reducing kernel modules in configuration
- Split large builds into separate kernel and image jobs

### Build Fails: Kernel Compilation Error

Check the kernel source compatibility:
- Verify `KERNEL_BRANCH` is correct in workflow file
- Ensure cross-compiler version matches kernel requirements
- Review kernel build logs in GitHub Actions

### Build Fails: Mount/Unmount Errors

Loop device issues can occur:
- The workflow uses `if: always()` to ensure cleanup
- Check that base image has expected partition layout
- Verify image URL is accessible and not corrupted

### Image Won't Boot

Verify installation:
1. Check SHA256 checksum matches
2. Ensure complete image write: `sync` before ejecting
3. Verify CM5 is properly seated in uConsole
4. Check power supply is adequate (5V 3A recommended)

## Security Considerations

### Supply Chain Security

The pipeline:
- Uses official ARM GCC toolchain from developer.arm.com
- Pulls kernel source from known GitHub repositories
- Downloads base image from official Radxa releases

### Recommendations

1. **Verify checksums**: Always check SHA256 before flashing
2. **Review source**: Inspect kernel and overlay repositories for security
3. **Use release tags**: Pin to specific commits instead of branches (optional)
4. **Sign images**: Consider adding GPG signature generation (future enhancement)

## CI/CD Best Practices

### Optimization for Free Tier

- **Manual dispatch only**: Prevents accidental builds consuming minutes
- **Minimal runners**: Uses standard ubuntu-22.04 (no large runners needed)
- **Artifact retention**: 30 days to minimize storage costs
- **Build caching**: Not implemented due to GitHub Actions cache limits (10GB)

### Monitoring

Monitor build status:
- Check Actions tab for build progress
- Review logs for warnings or errors
- Download artifacts immediately after successful builds

## Contributing

### Reporting Issues

When reporting build failures:
1. Include full workflow run URL
2. Attach relevant log sections
3. Specify input parameters used
4. Note any customizations made

### Pull Requests

Contributions welcome for:
- Kernel configuration improvements
- Additional device tree overlays
- Build optimization
- Documentation updates

## License

This build pipeline is provided under GPL-2.0 license (same as Linux kernel).

See individual source repositories for their specific licenses:
- Kernel: GPL-2.0
- Overlays: GPL-2.0

## References

- [Radxa CM5 Documentation](https://docs.radxa.com/en/compute-module/cm5/)
- [ClockworkPi uConsole](https://www.clockworkpi.com/uconsole)
- [Radxa Build System](https://github.com/radxa-build)
- [Device Tree Overlays](https://docs.radxa.com/en/radxa-os/rsetup/devicetree)

## Support

For hardware-specific issues:
- [ClockworkPi Forums](https://forum.clockworkpi.com/)
- [Radxa Forums](https://forum.radxa.com/)

For build pipeline issues:
- Open GitHub Issues in this repository
- Include workflow run ID and error logs

---

**Last Updated**: January 2025  
**Pipeline Version**: 1.0
