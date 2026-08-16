# uConsole CM5 Deployment Acceptance

Target identity: `Radxa CM5 RPI CM4 IO` at `192.168.0.146`.
Operator host `bugoutbox` / `192.168.0.10` is explicitly out of target scope.

## Reproducible build

- Radxa rkr5.1 kernel CI: [run 31871935060](https://github.com/SpootyMcSpoot/uconsole-radaxa-cm5/actions/runs/31871935060), passed at commit `8e49015`.
- Installed kernel package SHA-256: `e2d7b35bb09a76c1e1b90d3ef176580969536679ff2c0c88087eb56b35c8c8f9`.
- Installed rkr5.1 panel module SHA-256: `1ed700f52d717351742a083c25fdf32f922301c16b84e7c5621f33861f59a488`.
- Final rkr5.1 Debian CI: [run 31873951514](https://github.com/SpootyMcSpoot/uconsole-radaxa-cm5/actions/runs/31873951514), passed by reusing run `31871935060`'s kernel artifact.
- Final rkr5.1 compressed image SHA-256: `bb2057b56e7eb23f54e11961fc380738d5eff0a6f4f8851dd5bdc1b5e855ac05`.
- Final rkr5.1 raw image SHA-256: `e4f8a481724c54a1b83dce8cd4235624b12389f8bd1e25f800028eff7920a742`.
- Kernel CI: [run 31846652709](https://github.com/SpootyMcSpoot/uconsole-radaxa-cm5/actions/runs/31846652709), passed.
- Kernel image SHA-256: `a752fef71aab9eab5b5778b316a14f1776d9f9d10899b09335a04bcf903859c7`.
- Installed panel module SHA-256: `533f42f0d9ae2e268bf951d323a60f703a4ea2bb05abf3856f3133fbbe128fde`.
- Final Debian CI: [run 31864273128](https://github.com/SpootyMcSpoot/uconsole-radaxa-cm5/actions/runs/31864273128), passed.
- Compressed image SHA-256: `900e7370677510922e1b9eadd597a0d8618b18f0172fc51468680c1b5e794124`.
- Raw image SHA-256: `675ba7f76f8b0f8169b6c2bc1c48b953418cf33dbd061d0bd4658136cea33d64`.

## Acceptance matrix

| Surface | Evidence | Status |
| --- | --- | --- |
| Target safety | Local address `.10` refused before SSH; exact device-tree model required before mutation | PASS |
| Maskrom automation | Exact RK3588 Maskrom VID/PID, single-device gate, image SHA, full image-sized eMMC readback SHA | READY; destructive replay not repeated against configured live unit |
| Boot/kernel | Live aarch64 CM5, permanent Radxa rkr5.1 `6.1.115-gf87fca6cefcb-dirty`; prior kernels retained as `l1/l2` recovery entries | PASS |
| Current root storage | `/dev/mmcblk1p3`, 228.9 GiB filesystem, 214.2 GiB available | PASS |
| Panel/display | Backlight 5/9, connected DSI 720x1280, LightDM active, Xorg DSI scanout, zero command-interface/panel-init errors | PASS (software); physical observation unconfirmed |
| HackerGadgets | AIO2 package/controller, pinctrl, rail service, SDR/USB GPIO high | PASS |
| Expansion USB/Wi-Fi | MT7921 driver, AC1200 USB enumeration and wireless interface | PASS |
| Radio/GPS tools | Meshtastic daemon/UI, SDR++, tar1090, PyGPSClient | PASS |
| SHTF box | arm64 package installed; service enabled/active; health API HTTP 200; staging rooted at `/content` | PASS |
| System health | No failed systemd units | PASS |
| NVMe `/content` storage | New external supply plus two 18650 cells eliminated the prior 38–41 second controller loss. Existing 2 TB ext4 filesystem adopted without formatting; UUID `2f1cf13e-c7d2-4dfa-9bb5-2c27167f522b` persisted at `/content` after reboot. Boundary reads, two 512 MiB and one post-reboot 1 GiB direct write/read tests passed; zero NVMe error signatures | PASS; firmware remains `5B2QJXD7`, so keep qualified power setup and update to `8B2QJXD7` when a stable native M.2 host is available |
| RTC | PCF85063 at I2C7 `0x51` reports chip absent; no `/dev/rtc*` | BLOCKED: hardware absent |

Latest repeatable image run `31873951514` passed at commit `8e49015`, reusing
the passed kernel artifact rather than recompiling. Cached artifact SHA-256:
raw `e4f8a481724c54a1b83dce8cd4235624b12389f8bd1e25f800028eff7920a742`;
XZ `bb2057b56e7eb23f54e11961fc380738d5eff0a6f4f8851dd5bdc1b5e855ac05`.

## Repeatable operation

Use `scripts/fetch-uconsole-image.sh` for cache-aware artifact download,
compressed/raw checksum validation, and decompression. Then use
`scripts/deploy-uconsole.sh` for flash, post-switch boot wait, CM5 identity,
package provisioning, optional verified arm64 SHTF package installation,
optional 2 TB NVMe `/content` initialization, reboot detection by changed boot ID, and final
validation. The physical Maskrom switch and power cycle are the only manual
transition.

Never pass `--nvme-storage` until `/dev/nvme0n1` exists and reports the expected
2 TB device. Initialization is destructive to the explicitly named NVMe; the
OS remains on eMMC.

Use `--adopt-nvme-storage` for an existing ext4 `p1`. Legacy Samsung 990 PRO
firmware additionally requires `--allow-legacy-990-pro-firmware`; this path
never formats media and performs a 512 MiB live-power qualification before
changing `/etc/fstab`.

## 2026-08-16 live NVMe acceptance packet

Environment: physical uConsole CM5 at `192.168.0.146`, operator host
`bugoutbox`, Radxa rkr5.1 kernel `6.1.115-gf87fca6cefcb-dirty`, OS/root on
`/dev/mmcblk1p3`, new external power supply, both 18650 cells installed, Samsung
990 PRO 2 TB firmware `5B2QJXD7`. Successful setup evidence lives on target at
`/var/log/uconsole-nvme-storage-20260816T224939Z/`; post-reboot validation SHA-256
is `64250c48d81c49ad0ba9f6659f9e6db0d18afb933b306d033496e338530ff8a0`.

| Surface | Owner | Action / input | Expected result | Authoritative readback | Negative / recovery case | Status |
| --- | --- | --- | --- | --- | --- | --- |
| Target boundary | Provisioner | Connect to `192.168.0.146` | Only exact CM5 may mutate | Device-tree model `Radxa CM5 RPI CM4 IO`; root `/dev/mmcblk1p3` | Local addresses and non-CM5 models rejected before mutation | PASS |
| Existing filesystem | NVMe helper | `--adopt-nvme-storage /dev/nvme0n1` | Preserve ext4 p1; no format | `e2fsck -fn` clean; existing directories retained; UUID unchanged | Exactly-one-partition and ext4 gates reject mismatches | PASS |
| Legacy-firmware power | NVMe helper | Explicit legacy override | Stable boundary and filesystem I/O | First/end 4 KiB reads, repeated 512 MiB direct write/read, device present | Kernel NVMe error signatures abort and trigger rollback | PASS |
| Persistence | systemd/fstab | Reboot after adoption | eMMC boots; UUID mounts at `/content` | New boot ID `7cd93492-cc8d-43f6-81e8-d61cecbaca87`; `/content` on `/dev/nvme0n1p1`; 1 GiB direct I/O passed | `nofail` preserves eMMC boot if NVMe is absent | PASS |
| SHTF integration | `shtf-box.service` | Start after content mount | Never use fallback eMMC `/content` | `RequiresMountsFor=/content`; enabled/active; HTTP health 200 | First immediate health probe failed; rollback restored eMMC; bounded readiness wait fixed race; retry passed | PASS |
| Hardware stack | Validator | Run after reboot and I/O | All installed hardware/software gates pass | 31 PASS, zero failed units, zero NVMe errors | RTC probe reports absent hardware | PASS except optional RTC BLOCKED |

## Researched sources

- [ClockworkPi forum: Radxa CM5 with HackerGadgets AIO2](https://forum.clockworkpi.com/t/uconsole-with-radxa-cm5-lastest-hackergadgets-aio2-board/21351/2)
- [ResistanceIsUseless/uconsole-radaxa-cm5](https://github.com/ResistanceIsUseless/uconsole-radaxa-cm5)
- [AK-Rex ClockworkRadxa Linux](https://github.com/ak-rex/ClockworkRadxa-linux)
- [Radxa kernel rkr5.1](https://github.com/radxa/kernel/tree/linux-6.1-stan-rkr5.1)
- [HackerGadgets AIO2 controller](https://github.com/hackergadgets/aiov2_ctl)
- [Radxa CM5 download documentation](https://docs.radxa.com/en/compute-module/cm5/download)
- [Samsung 990 PRO firmware downloads and release notes](https://semiconductor.samsung.com/consumer-storage/support/tools/)
- [Samsung 990 PRO data sheet](https://download.semiconductor.samsung.com/resources/data-sheet/samsung_nvme_ssd_990_pro_datasheet_rev.2.0.pdf)
