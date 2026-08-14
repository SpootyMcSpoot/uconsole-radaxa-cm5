#!/bin/bash

set -euo pipefail

KERNEL_DIR="${1:?usage: install-cwu50-new-panel-driver.sh KERNEL_DIR}"
DRIVER_REF="5633aedcb3fd632d64c54db0184880d1954de62b"
DRIVER_SHA256="db451e742bb60a005c126688fb8c4b0cb239ead465264d35ac88902f6a953ba3"
DRIVER_URL="https://raw.githubusercontent.com/ak-rex/rpi-linux/${DRIVER_REF}/drivers/gpu/drm/panel/panel-cwu50.c"
TARGET="${KERNEL_DIR}/drivers/gpu/drm/panel/panel-cwu50.c"
TEMP_DRIVER="$(mktemp)"
trap 'rm -f "${TEMP_DRIVER}"' EXIT

wget -q -O "${TEMP_DRIVER}" "${DRIVER_URL}"
printf '%s  %s\n' "${DRIVER_SHA256}" "${TEMP_DRIVER}" | sha256sum -c -

# drm_panel.prepare_prev_first was added after the pinned Radxa 6.1 tree.
# Panel sequencing remains controlled by the existing Radxa DSI bridge.
sed -i '/ctx->panel\.prepare_prev_first = true;/d' "${TEMP_DRIVER}"

# The Raspberry Pi tree does not promote unused variables to errors.  Its
# driver carries five declarations that are never referenced; Radxa's kernel
# builds with -Werror, so remove only those declarations from their functions.
sed -i \
  -e '/^static int cwu50_init_sequence2/,/^}/ {/^[[:space:]]*int err;$/d;}' \
  -e '/^static int cwu50_disable/,/^}/ {/^[[:space:]]*struct mipi_dsi_device \*dsi =/d; /^[[:space:]]*int ret;$/d;}' \
  -e '/^static int cwu50_enable/,/^}/ {/^[[:space:]]*struct mipi_dsi_device \*dsi =/d; /^[[:space:]]*int ret;$/d;}' \
  "${TEMP_DRIVER}"

# GPIO1_B4 already identifies the panel revision before attach on the CM5.  The
# Raspberry Pi driver's redundant DCS register read wedges the RK3588 DSI2 CRI
# receive path; every subsequent initialization write then times out.  Keep the
# GPIO result authoritative on this host and avoid that unsupported read.
sed -i \
  -e '/^static int cwu50_prepare/,/^}/ {/^[[:space:]]*u8 buf\[4\];$/d; s/^[[:space:]]*dcs_write_seq(0xE0,0x00);$/\t\/\* GPIO panel ID is authoritative on RK3588; avoid the CRI RX read. \*\//; /mipi_dsi_dcs_read(dsi, 0x04, buf, 3);/d; /if(buf\[0\] == 0x39) ctx->is_new_panel = 1;/d;}' \
  "${TEMP_DRIVER}"

grep -q 'cwu50_init_sequence2' "${TEMP_DRIVER}"
grep -q 'is_new_panel' "${TEMP_DRIVER}"
grep -q 'GPIO panel ID is authoritative on RK3588' "${TEMP_DRIVER}"
if sed -n '/^static int cwu50_prepare/,/^}/p' "${TEMP_DRIVER}" | grep -Eq 'u8 buf\[4\]|mipi_dsi_dcs_read'; then
  exit 1
fi
if sed -n '/^static int cwu50_init_sequence2/,/^}/p' "${TEMP_DRIVER}" | grep -q 'int err;'; then
  exit 1
fi
if sed -n '/^static int cwu50_disable/,/^}/p' "${TEMP_DRIVER}" | grep -Eq 'mipi_dsi_device \*dsi|int ret;'; then
  exit 1
fi
if sed -n '/^static int cwu50_enable/,/^}/p' "${TEMP_DRIVER}" | grep -Eq 'mipi_dsi_device \*dsi|int ret;'; then
  exit 1
fi
install -m 0644 "${TEMP_DRIVER}" "${TARGET}"
