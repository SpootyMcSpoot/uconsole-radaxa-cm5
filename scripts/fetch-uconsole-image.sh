#!/bin/bash
set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/fetch-uconsole-image.sh --run-id ID [options]

Options:
  --repo OWNER/REPO   GitHub repository (default: SpootyMcSpoot/uconsole-radaxa-cm5)
  --output-dir DIR    Cache directory (default: ./uconsole-staging/run-ID)

Downloads the debian-image artifact only when absent, stages GitHub CLI's ZIP
inside the cache instead of quota-limited /tmp, verifies compressed SHA/XZ,
retains the raw image, and verifies or generates its SHA-256 sidecar.
EOF
}

run_id=""
repo=SpootyMcSpoot/uconsole-radaxa-cm5
output_dir=""
while (($#)); do
    case "$1" in
        --run-id) run_id=${2:-}; shift 2 ;;
        --repo) repo=${2:-}; shift 2 ;;
        --output-dir) output_dir=${2:-}; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

[[ $run_id =~ ^[1-9][0-9]*$ ]] || { echo "Invalid --run-id" >&2; exit 2; }
[[ $repo =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "Invalid --repo" >&2; exit 2; }
[[ -n $output_dir ]] || output_dir="$PWD/uconsole-staging/run-$run_id"
for command in gh sha256sum xz find; do
    command -v "$command" >/dev/null || { echo "Missing command: $command" >&2; exit 1; }
done

mkdir -p "$output_dir" "$output_dir/.tmp"
mapfile -t compressed_images < <(find "$output_dir" -maxdepth 1 -type f -name '*.img.xz' -print)
if ((${#compressed_images[@]} == 0)); then
    TMPDIR="$output_dir/.tmp" gh run download "$run_id" -R "$repo" \
        -n debian-image -D "$output_dir"
    mapfile -t compressed_images < <(find "$output_dir" -maxdepth 1 -type f -name '*.img.xz' -print)
else
    echo "PASS cached artifact present"
fi
((${#compressed_images[@]} == 1)) || {
    echo "Expected exactly one compressed image; found ${#compressed_images[@]}" >&2
    exit 1
}

compressed=${compressed_images[0]}
compressed_sidecar="$compressed.sha256"
[[ -s $compressed_sidecar ]] || { echo "Missing compressed SHA sidecar" >&2; exit 1; }
(
    cd "$output_dir"
    sha256sum -c "$(basename "$compressed_sidecar")"
)
xz -t "$compressed"

raw=${compressed%.xz}
[[ -s $raw ]] || xz -dk "$compressed"
raw_sidecar="$raw.sha256"
if [[ ! -s $raw_sidecar ]]; then
    raw_sha=$(sha256sum "$raw" | awk '{print $1}')
    printf '%s  %s\n' "$raw_sha" "$(basename "$raw")" >"$raw_sidecar"
fi
(
    cd "$output_dir"
    sha256sum -c "$(basename "$raw_sidecar")"
)

printf 'RAW_IMAGE=%s\n' "$raw"
printf 'RAW_SHA256=%s\n' "$(awk '{print $1}' "$raw_sidecar")"
