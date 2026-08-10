# ARC: Radxa CM5 uConsole black screen

## Failure capture

- Gate: first hardware boot after full eMMC flash/readback
- Observed: uConsole screen remains black; no recovery USB after MASKROM-off reboot
- Build commit: `69a2b97fd847c54f423975b668c9929096e3840a`
- CI run: `31107126040`
- Raw image SHA-256: `ca53141634dcd2670779cae831f7420df12de8a8331ad1d2b410a4baeda66e34`
- Flash validation: full 9,276,250-sector readback and `cmp` passed
- Boot contract: default extlinux entry references `axp20x.dtbo`,
  `cwu50_panel.dtbo`, and `displaystuff.dtbo`
- Host guard: `bugoutbox` / `192.168.0.10` is localhost and excluded

## Hypothesis ledger

| Category | Hypothesis | Evidence for | Evidence against | Confidence | Smallest discriminating experiment |
|---|---|---|---|---|---|
| Contract / implementation | Radxa 6.1 CWU50 driver lacks newest-panel init sequence | Radxa driver is 477 lines with one init path; current AK-Rex RPi driver is 846 lines with panel-ID GPIO, `is_new_panel`, and `cwu50_init_sequence2`; Rex confirmed on 2026-06-07 that current Radxa image only supports first two panel revisions | Exact installed panel revision not readable without working kernel/console | High | Compile pinned AK-Rex new-panel driver against pinned Radxa kernel; boot resulting image |
| Boot configuration | U-Boot did not apply overlays | Offline extlinux and DTBO checks prove files/references, but not runtime application | Correct normal entry contains all three `fdtoverlays` paths | Medium | Capture UART/HDMI boot log or boot corrected image with panel output |
| Hardware / power | AIO2 power, ribbon, or battery prevents panel initialization | Forum documents CM5 power sensitivity and AIO2 USB-C power issue | MASKROM USB and multi-GB flash/readback were stable; same symptom is documented for unsupported panel | Low-medium | If corrected driver still fails, inspect HDMI/UART and power LEDs/rails before another software change |
| OS/network | OS booted but only panel is dark | CM5 has no internal Wi-Fi/BT; external MT7921U has no saved network, so absent SSH does not prove boot failure | No serial/HDMI evidence yet | Medium | Establish display with new driver or attach UART/HDMI |
| Package contract | HackerGadgets hardware stack is not preinstalled | Current image only stages installer and base support packages | None | Certain | Install and assert AIO2 package, recommended apps, controller, firmware, and services inside image chroot |

## Supported fix direction

1. Backport pinned new-panel driver from AK-Rex `rpi-linux` commit
   `5633aedcb3fd632d64c54db0184880d1954de62b` into pinned Radxa kernel.
2. Preserve MT7921U, Bluetooth USB, NVMe, and panel kernel config assertions.
3. Expand image root filesystem, then preinstall HackerGadgets AIO2 package and
   all recommended companion packages inside image chroot only.
4. Verify packages, services, firmware, boot files, driver content, filesystem,
   checksum, flash readback, display, NVMe, Wi-Fi, and AIO2 hardware.

