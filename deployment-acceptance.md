# uConsole CM5 Deployment Acceptance

Target identity: `Radxa CM5 RPI CM4 IO` at `192.168.0.146`.
Operator host `bugoutbox` / `192.168.0.10` is explicitly out of target scope.

## Reproducible build

- Kernel CI: [run 31846652709](https://github.com/SpootyMcSpoot/uconsole-radaxa-cm5/actions/runs/31846652709), passed.
- Kernel image SHA-256: `a752fef71aab9eab5b5778b316a14f1776d9f9d10899b09335a04bcf903859c7`.
- Installed panel module SHA-256: `533f42f0d9ae2e268bf951d323a60f703a4ea2bb05abf3856f3133fbbe128fde`.
- Final Debian CI: [run 31854866795](https://github.com/SpootyMcSpoot/uconsole-radaxa-cm5/actions/runs/31854866795), passed.
- Compressed image SHA-256: `37f36522bc4c4874901ab7ebd1e24d04204e61aa1f87482fc09b72938cd80d14`.
- Raw image SHA-256: `804b4fe47a66fd54d7047dd72b2faaa310d3d5155260c1e50095429aea3e727c`.

## Acceptance matrix

| Surface | Evidence | Status |
| --- | --- | --- |
| Target safety | Local address `.10` refused before SSH; exact device-tree model required before mutation | PASS |
| Maskrom automation | Exact RK3588 Maskrom VID/PID, single-device gate, image SHA, full image-sized eMMC readback SHA | READY; destructive replay not repeated against configured live unit |
| Boot/kernel | Live aarch64 CM5, permanent `6.1.84-gd142501df0e9-dirty`, no DSI command errors | PASS |
| Current root storage | `/dev/mmcblk1p3`, 228.9 GiB filesystem, 214.2 GiB available | PASS |
| Panel/display | Backlight, connected DSI 720x1280, LightDM active, Xorg DSI scanout; XWD greeter readback rendered | PASS (software); physical observation unconfirmed |
| HackerGadgets | AIO2 package/controller, pinctrl, rail service, SDR/USB GPIO high | PASS |
| Expansion USB/Wi-Fi | MT7921 driver, AC1200 USB enumeration and wireless interface | PASS |
| Radio/GPS tools | Meshtastic daemon/UI, SDR++, tar1090, PyGPSClient | PASS |
| SHTF box | arm64 package installed; service enabled/active; health API HTTP 200; staging rooted at `/content` | PASS |
| System health | No failed systemd units | PASS |
| NVMe root | No NVMe block device or PCI endpoint; PCIe remains at receiver-detect | BLOCKED: hardware endpoint absent |
| RTC | PCF85063 at I2C7 `0x51` reports chip absent; no `/dev/rtc*` | BLOCKED: hardware absent |

## Repeatable operation

Use `scripts/fetch-uconsole-image.sh` for cache-aware artifact download,
compressed/raw checksum validation, and decompression. Then use
`scripts/deploy-uconsole.sh` for flash, post-switch boot wait, CM5 identity,
package provisioning, optional verified arm64 SHTF package installation,
optional NVMe migration, reboot detection by changed boot ID, and final
validation. The physical Maskrom switch and power cycle are the only manual
transition.

Never pass `--migrate-nvme` until `/dev/nvme0n1` exists and reports the expected
2 TB device. Migration is destructive to the explicitly named NVMe device.

## Researched sources

- [ClockworkPi forum: Radxa CM5 with HackerGadgets AIO2](https://forum.clockworkpi.com/t/uconsole-with-radxa-cm5-lastest-hackergadgets-aio2-board/21351/2)
- [ResistanceIsUseless/uconsole-radaxa-cm5](https://github.com/ResistanceIsUseless/uconsole-radaxa-cm5)
- [AK-Rex ClockworkRadxa Linux](https://github.com/ak-rex/ClockworkRadxa-linux)
- [HackerGadgets AIO2 controller](https://github.com/hackergadgets/aiov2_ctl)
- [Radxa CM5 download documentation](https://docs.radxa.com/en/compute-module/cm5/download)
