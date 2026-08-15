#!/bin/bash
set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/deploy-uconsole.sh --image IMAGE.img --loader LOADER.bin --host HOST [options]

Options:
  --sha256 DIGEST      Published raw-image SHA-256
  --user USER          SSH user (default: radxa)
  --wait-seconds N     Maximum wait after each reboot (default: 900)
  --migrate-nvme DEV   Migrate root after provisioning (destructive to DEV)
  --skip-flash         Provision/validate an already booted target

Set SSHPASS and SUDO_PASSWORD for password authentication. The script flashes
one exact RK3588 Maskrom target, waits for the physical Maskrom-off reboot,
requires exact Radxa CM5 identity, provisions packages, optionally migrates to
NVMe, then runs full validation. No target script executes on the operator host.
EOF
}

image=""
loader=""
expected_sha=""
host=""
user=radxa
wait_seconds=900
nvme_device=""
skip_flash=false
while (($#)); do
    case "$1" in
        --image) image=${2:-}; shift 2 ;;
        --loader) loader=${2:-}; shift 2 ;;
        --sha256) expected_sha=${2:-}; shift 2 ;;
        --host) host=${2:-}; shift 2 ;;
        --user) user=${2:-}; shift 2 ;;
        --wait-seconds) wait_seconds=${2:-}; shift 2 ;;
        --migrate-nvme) nvme_device=${2:-}; shift 2 ;;
        --skip-flash) skip_flash=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

[[ -n $host ]] || { echo "Missing --host" >&2; exit 2; }
[[ $wait_seconds =~ ^[1-9][0-9]*$ ]] || { echo "Invalid --wait-seconds" >&2; exit 2; }
[[ $host != localhost && $host != 127.* && $host != ::1 ]] || {
    echo "Refusing localhost target: $host" >&2
    exit 2
}
mapfile -t target_ips < <(getent ahostsv4 "$host" | awk '{print $1}' | sort -u)
((${#target_ips[@]} > 0)) || { echo "Cannot resolve target: $host" >&2; exit 1; }
read -r -a local_ips <<<"$(hostname -I 2>/dev/null || true)"
for target_ip in "${target_ips[@]}"; do
    for local_ip in "${local_ips[@]}"; do
        [[ $target_ip != "$local_ip" ]] || {
            echo "Refusing local host address: $target_ip" >&2
            exit 1
        }
    done
done

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
flash_script="$script_dir/flash-uconsole-maskrom.sh"
provision_script="$script_dir/provision-uconsole-over-ssh.sh"

wait_for_target() {
    local deadline=$((SECONDS + wait_seconds))
    echo "Waiting for verified Radxa CM5 target at $host ..."
    until "$provision_script" --host "$host" --user "$user" --identity-only >/dev/null 2>&1; do
        ((SECONDS < deadline)) || { echo "Timed out waiting for verified target: $host" >&2; return 1; }
        sleep 5
    done
    "$provision_script" --host "$host" --user "$user" --identity-only
}

if [[ $skip_flash == false ]]; then
    [[ -n $image && -n $loader ]] || { echo "--image and --loader are required" >&2; exit 2; }
    flash_args=(--image "$image" --loader "$loader")
    [[ -z $expected_sha ]] || flash_args+=(--sha256 "$expected_sha")
    if [[ $EUID -eq 0 ]]; then
        "$flash_script" "${flash_args[@]}"
    else
        sudo "$flash_script" "${flash_args[@]}"
    fi
    echo "ACTION REQUIRED: turn Maskrom switch OFF, then power-cycle uConsole. Waiting automatically."
fi

wait_for_target
"$provision_script" --host "$host" --user "$user" --provision --allow-emmc --no-validate

if [[ -n $nvme_device ]]; then
    "$provision_script" --host "$host" --user "$user" --migrate-nvme "$nvme_device" --reboot
    wait_for_target
fi

"$provision_script" --host "$host" --user "$user"
