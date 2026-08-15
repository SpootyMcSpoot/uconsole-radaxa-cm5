#!/bin/bash
set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/provision-uconsole-over-ssh.sh --host HOST [options]

Options:
  --user USER          SSH user (default: radxa)
  --provision          Run idempotent HackerGadgets/XFCE provisioning
  --allow-emmc         Permit package provisioning on eMMC root
  --migrate-nvme DEV   Migrate root to exact NVMe device (destructive)
  --nvme-storage DEV   Format expected 2 TB NVMe and mount it at /content
  --shtf-deb FILE      Install verified arm64 shtf-box package
  --reboot             Reboot after successful provisioning
  --identity-only      Stop after local-address and target-model checks
  --print-boot-id      Print boot ID after target-model check, then stop
  --no-validate        Skip final hardware validation

Set SSHPASS for password SSH and SUDO_PASSWORD for remote sudo. SSH keys and
passwordless sudo also work. Script rejects loopback and every local host IP,
then requires exact Radxa CM5 device-tree identity before remote mutation.
EOF
}

host=""
user=radxa
provision=false
allow_emmc=false
nvme_device=""
nvme_storage_device=""
shtf_deb=""
reboot=false
identity_only=false
print_boot_id=false
validate=true
while (($#)); do
    case "$1" in
        --host) host=${2:-}; shift 2 ;;
        --user) user=${2:-}; shift 2 ;;
        --provision) provision=true; shift ;;
        --allow-emmc) allow_emmc=true; shift ;;
        --migrate-nvme) nvme_device=${2:-}; shift 2 ;;
        --nvme-storage) nvme_storage_device=${2:-}; shift 2 ;;
        --shtf-deb) shtf_deb=${2:-}; shift 2 ;;
        --reboot) reboot=true; shift ;;
        --identity-only) identity_only=true; shift ;;
        --print-boot-id) print_boot_id=true; shift ;;
        --no-validate) validate=false; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

[[ -n $host && $host != localhost && $host != 127.* && $host != ::1 ]] || {
    echo "Refusing localhost or empty target: $host" >&2
    exit 2
}
[[ $user =~ ^[a-z_][a-z0-9_-]*$ ]] || { echo "Invalid SSH user" >&2; exit 2; }
[[ -z $nvme_device || -z $nvme_storage_device ]] || {
    echo "Choose either root migration or /content storage, not both" >&2
    exit 2
}
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [[ -n $nvme_storage_device ]]; then
    [[ -x $script_dir/target/uconsole-bootstrap-nvme-storage ]] || {
        echo "Missing target helper: $script_dir/target/uconsole-bootstrap-nvme-storage" >&2
        exit 1
    }
fi
if [[ -n $shtf_deb ]]; then
    [[ -f $shtf_deb && -s $shtf_deb ]] || { echo "Invalid SHTF package: $shtf_deb" >&2; exit 2; }
    for command in ar tar awk; do
        command -v "$command" >/dev/null || { echo "Missing command: $command" >&2; exit 1; }
    done
    control_member=$(ar t "$shtf_deb" | awk '/^control[.]tar([.].+)?$/ {print; exit}')
    [[ -n $control_member ]] || { echo "Invalid Debian package control archive" >&2; exit 2; }
    case "$control_member" in
        *.zst) control_data=$(ar p "$shtf_deb" "$control_member" | tar --zstd -xOf - ./control) ;;
        *.xz) control_data=$(ar p "$shtf_deb" "$control_member" | tar -JxOf - ./control) ;;
        *.gz) control_data=$(ar p "$shtf_deb" "$control_member" | tar -zxOf - ./control) ;;
        *.bz2) control_data=$(ar p "$shtf_deb" "$control_member" | tar -jxOf - ./control) ;;
        *.tar) control_data=$(ar p "$shtf_deb" "$control_member" | tar -xOf - ./control) ;;
        *) echo "Unsupported Debian control compression: $control_member" >&2; exit 2 ;;
    esac
    package_name=$(awk '$1 == "Package:" {print $2; exit}' <<<"$control_data")
    package_arch=$(awk '$1 == "Architecture:" {print $2; exit}' <<<"$control_data")
    [[ $package_name == shtf-box ]] || { echo "Not a shtf-box package" >&2; exit 2; }
    [[ $package_arch == arm64 ]] || { echo "SHTF package is not arm64" >&2; exit 2; }
fi

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

ssh_cmd=(ssh)
if [[ -n ${SSHPASS:-} ]]; then
    command -v sshpass >/dev/null || { echo "SSHPASS set but sshpass missing" >&2; exit 1; }
    ssh_cmd=(sshpass -e ssh)
fi
known_hosts=$(mktemp --tmpdir uconsole-known-hosts.XXXXXX)
trap 'rm -f "$known_hosts"' EXIT
ssh_opts=(-F /dev/null -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="$known_hosts")
remote=("${ssh_cmd[@]}" "${ssh_opts[@]}" "$user@$host")
scp_cmd=(scp)
[[ -z ${SSHPASS:-} ]] || scp_cmd=(sshpass -e scp)

model=$("${remote[@]}" "tr -d '\\0' </proc/device-tree/model")
[[ $model == "Radxa CM5 RPI CM4 IO" ]] || {
    echo "Refusing non-target host: $host reports '$model'" >&2
    exit 1
}
if [[ $print_boot_id == true ]]; then
    "${remote[@]}" cat /proc/sys/kernel/random/boot_id
    exit 0
fi
printf 'PASS target identity: %s (%s)\n' "$model" "$host"
[[ $identity_only == false ]] || exit 0

sudo_remote() {
    local command=$1
    local quoted_command
    printf -v quoted_command '%q' "$command"
    if [[ -n ${SUDO_PASSWORD:-} ]]; then
        printf '%s\n' "$SUDO_PASSWORD" | "${remote[@]}" "sudo -S -p '' /bin/bash -c $quoted_command"
    else
        "${remote[@]}" "sudo -n /bin/bash -c $quoted_command"
    fi
}

if [[ -n $nvme_device ]]; then
    [[ $nvme_device =~ ^/dev/nvme[0-9]+n[0-9]+$ ]] || {
        echo "Invalid NVMe device: $nvme_device" >&2
        exit 2
    }
    "${remote[@]}" "test -b '$nvme_device' && lsblk -dn -o NAME,SIZE,MODEL '$nvme_device'"
    sudo_remote "/usr/local/sbin/uconsole-bootstrap-nvme-root --device '$nvme_device' --yes"
    reboot=true
fi

if [[ $provision == true ]]; then
    install_args=""
    [[ $allow_emmc == false ]] || install_args="--allow-emmc"
    sudo_remote "/usr/local/sbin/uconsole-install-hackergadgets $install_args"
fi

if [[ -n $shtf_deb ]]; then
    "${scp_cmd[@]}" "${ssh_opts[@]}" "$shtf_deb" "$user@$host:/tmp/uconsole-shtf-box.deb"
    sudo_remote "apt-get install -y /tmp/uconsole-shtf-box.deb && systemctl enable --now shtf-box.service && rm -f /tmp/uconsole-shtf-box.deb"
fi

if [[ -n $nvme_storage_device ]]; then
    [[ $nvme_storage_device =~ ^/dev/nvme[0-9]+n[0-9]+$ ]] || {
        echo "Invalid NVMe device: $nvme_storage_device" >&2
        exit 2
    }
    "${scp_cmd[@]}" "${ssh_opts[@]}" \
        "$script_dir/target/uconsole-bootstrap-nvme-storage" \
        "$user@$host:/tmp/uconsole-bootstrap-nvme-storage"
    sudo_remote "install -m 0755 /tmp/uconsole-bootstrap-nvme-storage /usr/local/sbin/uconsole-bootstrap-nvme-storage && rm -f /tmp/uconsole-bootstrap-nvme-storage"
    "${remote[@]}" "test -b '$nvme_storage_device' && lsblk -dn -b -o NAME,SIZE,MODEL '$nvme_storage_device'"
    sudo_remote "/usr/local/sbin/uconsole-bootstrap-nvme-storage --device '$nvme_storage_device' --yes"
fi

if [[ $reboot == true ]]; then
    sudo_remote reboot || true
    echo "Reboot requested. Rerun without mutation flags after target returns."
    exit 0
fi

[[ $validate == false ]] || sudo_remote /usr/local/sbin/uconsole-validate-hardware
