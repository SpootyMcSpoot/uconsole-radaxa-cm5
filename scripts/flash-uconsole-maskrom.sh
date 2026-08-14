#!/bin/bash
set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage: sudo scripts/flash-uconsole-maskrom.sh --image IMAGE.img --loader LOADER.bin [--sha256 DIGEST]

Flashes exactly one RK3588 CM5 in Maskrom mode, reads back the full image-sized
LBA range, compares SHA-256, then reboots. Destructive only to detected Rockchip
Maskrom target. Refuses zero, multiple, Loader-mode, or unexpected USB devices.
EOF
}

image=""
loader=""
expected_sha=""
while (($#)); do
    case "$1" in
        --image) image=${2:-}; shift 2 ;;
        --loader) loader=${2:-}; shift 2 ;;
        --sha256) expected_sha=${2:-}; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

[[ $EUID -eq 0 ]] || { echo "Must run as root" >&2; exit 1; }
[[ -f $image && -s $image && $image == *.img ]] || { echo "Invalid raw image: $image" >&2; exit 2; }
[[ -f $loader && -s $loader ]] || { echo "Invalid RK3588 loader: $loader" >&2; exit 2; }
for command in rkdeveloptool sha256sum stat awk grep mktemp; do
    command -v "$command" >/dev/null || { echo "Missing command: $command" >&2; exit 1; }
done

image_size=$(stat -c %s "$image")
((image_size % 512 == 0)) || { echo "Image size is not LBA-aligned" >&2; exit 1; }
image_sha=$(sha256sum "$image" | awk '{print $1}')
if [[ -n $expected_sha ]]; then
    [[ $expected_sha =~ ^[0-9a-fA-F]{64}$ ]] || { echo "Invalid SHA-256" >&2; exit 2; }
    [[ ${image_sha,,} == "${expected_sha,,}" ]] || { echo "Image SHA-256 mismatch" >&2; exit 1; }
fi

devices=$(rkdeveloptool ld)
mapfile -t maskrom_devices < <(grep -E 'Vid=0x2207,Pid=0x350b.*Maskrom' <<<"$devices")
((${#maskrom_devices[@]} == 1)) || {
    printf 'Refusing: expected exactly one RK3588 Maskrom device; found %s\n' "${#maskrom_devices[@]}" >&2
    printf '%s\n' "$devices" >&2
    exit 1
}
[[ $(grep -c '^DevNo=' <<<"$devices") -eq 1 ]] || { echo "Refusing multiple Rockchip devices" >&2; exit 1; }
printf 'PASS Maskrom identity: %s\n' "${maskrom_devices[0]}"
printf 'PASS source image: size=%s sha256=%s\n' "$image_size" "$image_sha"

rkdeveloptool db "$loader"
for _ in {1..20}; do
    rkdeveloptool ld | grep -q 'Loader' && break
    sleep 1
done
rkdeveloptool ld | grep -q 'Loader' || { echo "Loader transition failed" >&2; exit 1; }
rkdeveloptool wl 0 "$image"

readback=$(mktemp --tmpdir uconsole-emmc-readback.XXXXXX.img)
cleanup() { [[ ! -e $readback ]] || echo "Readback retained: $readback" >&2; }
trap cleanup EXIT
blocks=$((image_size / 512))
rkdeveloptool rl 0 "$blocks" "$readback"
readback_sha=$(sha256sum "$readback" | awk '{print $1}')
[[ $readback_sha == "$image_sha" ]] || {
    echo "Readback SHA-256 mismatch: source=$image_sha readback=$readback_sha" >&2
    exit 1
}
printf 'PASS full eMMC readback: sha256=%s\n' "$readback_sha"
rm -f "$readback"
trap - EXIT
rkdeveloptool rd
echo "Flash complete. Turn Maskrom switch off before normal boot."
