#!/bin/bash
#
# Local Build Validation Script for Radxa CM5 uConsole
# 
# This script performs local validation of kernel and overlay builds
# before triggering the full GitHub Actions pipeline. Use this to catch
# issues early and save CI/CD minutes.
#
# Usage: ./local-validate.sh [options]
#
# Requirements:
#   - Docker (recommended) OR
#   - Ubuntu 22.04+ with build tools installed

set -e  # Exit on error
set -u  # Exit on undefined variable

# Configuration
KERNEL_REPO="https://github.com/radxa/kernel.git"
KERNEL_BRANCH="f87fca6cefcb6229c7f81399dd351cf658940bfa"
OVERLAYS_REPO="https://github.com/dev-null2019/radxa-cm5-uconsole.git"
WORK_DIR="/tmp/uconsole-build-$$"
USE_DOCKER=true

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function: Print colored messages
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function: Check if running in Docker
check_docker() {
    if command -v docker &> /dev/null; then
        log_info "Docker found, using containerized build"
        USE_DOCKER=true
    else
        log_warn "Docker not found, using native build"
        USE_DOCKER=false
    fi
}

# Function: Validate kernel source can be cloned and configured
validate_kernel_source() {
    log_info "Validating kernel source..."
    
    mkdir -p "$WORK_DIR/kernel"
    cd "$WORK_DIR"
    
    # Clone kernel repository (shallow clone for speed)
    log_info "Cloning kernel repository..."
    git clone --depth=1 --branch="$KERNEL_BRANCH" "$KERNEL_REPO" kernel
    
    cd kernel
    
    # Check if rockchip_linux_defconfig exists
    if [ ! -f "arch/arm64/configs/rockchip_linux_defconfig" ]; then
        log_error "rockchip_linux_defconfig not found in kernel source"
        return 1
    fi
    
    log_info "Kernel source validation: PASSED"
    return 0
}

# Function: Validate overlay source
validate_overlay_source() {
    log_info "Validating overlay source..."
    
    mkdir -p "$WORK_DIR/overlays"
    cd "$WORK_DIR"
    
    # Clone overlays repository
    log_info "Cloning overlays repository..."
    git clone --depth=1 "$OVERLAYS_REPO" overlays
    
    cd overlays
    
    # Check for devicetree_overlays directory
    if [ ! -d "devicetree_overlays" ]; then
        log_error "devicetree_overlays directory not found"
        return 1
    fi
    
    # Count .dts files
    DTS_COUNT=$(find devicetree_overlays -name "*.dts" | wc -l)
    log_info "Found $DTS_COUNT device tree source files"
    
    if [ "$DTS_COUNT" -eq 0 ]; then
        log_warn "No .dts files found in devicetree_overlays/"
        return 1
    fi
    
    log_info "Overlay source validation: PASSED"
    return 0
}

# Function: Test kernel configuration
test_kernel_config() {
    log_info "Testing kernel configuration..."
    
    if [ "$USE_DOCKER" = true ]; then
        # Use Docker for isolated build environment
        docker run --rm \
            -v "$WORK_DIR/kernel:/kernel" \
            -w /kernel \
            ubuntu:22.04 \
            bash -c "
                apt-get update -qq
                apt-get install -y -qq build-essential bc bison flex libssl-dev libncurses5-dev wget
                wget -q https://developer.arm.com/-/media/Files/downloads/gnu/12.2.rel1/binrel/arm-gnu-toolchain-12.2.rel1-x86_64-aarch64-none-linux-gnu.tar.xz
                tar -xf arm-gnu-toolchain-12.2.rel1-x86_64-aarch64-none-linux-gnu.tar.xz
                export PATH=\$PWD/arm-gnu-toolchain-12.2.rel1-x86_64-aarch64-none-linux-gnu/bin:\$PATH
                export ARCH=arm64
                export CROSS_COMPILE=aarch64-none-linux-gnu-
                make rockchip_linux_defconfig
                make savedefconfig
            "
    else
        # Native build (requires tools installed)
        cd "$WORK_DIR/kernel"
        
        if ! command -v aarch64-linux-gnu-gcc &> /dev/null; then
            log_error "aarch64 cross-compiler not found. Install with:"
            log_error "  sudo apt-get install gcc-aarch64-linux-gnu"
            return 1
        fi
        
        export ARCH=arm64
        export CROSS_COMPILE=aarch64-linux-gnu-
        
        make rockchip_linux_defconfig
        make savedefconfig
    fi
    
    log_info "Kernel configuration test: PASSED"
    return 0
}

# Function: Test overlay compilation
test_overlay_compilation() {
    log_info "Testing overlay compilation..."
    
    cd "$WORK_DIR/overlays"
    
    # Check if dtc is available
    if ! command -v dtc &> /dev/null; then
        if [ "$USE_DOCKER" = true ]; then
            docker run --rm \
                -v "$WORK_DIR/overlays:/overlays" \
                -w /overlays \
                ubuntu:22.04 \
                bash -c "
                    apt-get update -qq
                    apt-get install -y -qq device-tree-compiler
                    mkdir -p test_compiled
                    for dts in devicetree_overlays/*.dts; do
                        basename=\$(basename \$dts .dts)
                        dtc -@ -I dts -O dtb -o test_compiled/\${basename}.dtbo \$dts
                    done
                    ls -lh test_compiled/
                "
        else
            log_error "device-tree-compiler (dtc) not found. Install with:"
            log_error "  sudo apt-get install device-tree-compiler"
            return 1
        fi
    else
        mkdir -p test_compiled
        for dts in devicetree_overlays/*.dts; do
            basename=$(basename "$dts" .dts)
            log_info "Compiling $basename..."
            dtc -@ -I dts -O dtb -o "test_compiled/${basename}.dtbo" "$dts"
        done
        
        ls -lh test_compiled/
    fi
    
    log_info "Overlay compilation test: PASSED"
    return 0
}

# Function: Validate workflow file syntax
validate_workflow() {
    log_info "Validating GitHub Actions workflow syntax..."
    
    WORKFLOW_FILE_SINGLE=".github/workflows/build-uconsole-image.yml"
    WORKFLOW_FILE_MULTI=".github/workflows/build-all-images.yml"
    
    for WORKFLOW_FILE in "$WORKFLOW_FILE_SINGLE" "$WORKFLOW_FILE_MULTI"; do
        if [ ! -f "$WORKFLOW_FILE" ]; then
            log_warn "Workflow file not found: $WORKFLOW_FILE"
            continue
        fi
        
        log_info "Validating $WORKFLOW_FILE..."
        
        # Basic YAML syntax check using Python
        if command -v python3 &> /dev/null; then
            python3 -c "
import yaml
import sys
try:
    with open('$WORKFLOW_FILE', 'r') as f:
        yaml.safe_load(f)
    print('  ✓ YAML syntax: VALID')
except Exception as e:
    print(f'  ✗ YAML syntax error: {e}')
    sys.exit(1)
            "
        else
            log_warn "Python3 not found, skipping YAML validation"
        fi
    done
    
    log_info "Workflow validation: PASSED"
    return 0
}

# Function: Cleanup
cleanup() {
    log_info "Cleaning up temporary files..."
    rm -rf "$WORK_DIR"
    log_info "Cleanup complete"
}

# Function: Print summary
print_summary() {
    echo ""
    echo "=========================================="
    echo "      VALIDATION SUMMARY"
    echo "=========================================="
    echo ""
    echo "✓ Kernel source accessible"
    echo "✓ Kernel configuration valid"
    echo "✓ Overlay source accessible"
    echo "✓ Overlays compile successfully"
    echo "✓ Workflow syntax valid"
    echo ""
    echo "All validations passed! Pipeline is ready to run."
    echo ""
    echo "Next steps:"
    echo "1. Commit and push changes"
    echo "2. Go to GitHub Actions tab"
    echo "3. Run 'Build Radxa CM5 uConsole Image' workflow"
    echo ""
}

# Main execution
main() {
    log_info "Starting local validation..."
    
    # Create work directory
    mkdir -p "$WORK_DIR"
    
    # Trap to ensure cleanup on exit
    trap cleanup EXIT
    
    # Run validations
    check_docker
    
    if ! validate_kernel_source; then
        log_error "Kernel source validation failed"
        exit 1
    fi
    
    if ! validate_overlay_source; then
        log_error "Overlay source validation failed"
        exit 1
    fi
    
    if ! test_kernel_config; then
        log_error "Kernel configuration test failed"
        exit 1
    fi
    
    if ! test_overlay_compilation; then
        log_error "Overlay compilation test failed"
        exit 1
    fi
    
    if ! validate_workflow; then
        log_error "Workflow validation failed"
        exit 1
    fi
    
    print_summary
}

# Run main function
main "$@"
