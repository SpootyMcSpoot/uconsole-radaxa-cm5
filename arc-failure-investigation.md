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

## Backport compile gate

- Gate: kernel-only CI run `31356113641`, commit `6d486df`
- Result: failed while compiling `panel-cwu50.c`; all other observed output was
  warnings or continued compilation.
- Leading implementation hypothesis: Radxa enables `-Werror`, while the pinned
  Raspberry Pi driver contains five unused local declarations. Evidence: the
  compiler reported only `err` in `cwu50_init_sequence2`, plus `dsi` and `ret`
  in each of `cwu50_disable` and `cwu50_enable`.
- Contract hypothesis: the pinned driver otherwise uses an unsupported 6.1 API.
  Evidence against: the previously identified `prepare_prev_first` assignment
  was removed and no missing-field or missing-symbol error occurred.
- Infrastructure hypothesis: CI runner or cross-compiler failure. Evidence
  against: the build ran for 17 minutes and failed deterministically on those
  source warnings.
- Minimal experiment: remove only the five unused declarations, retain the
  panel-ID and second-init-sequence assertions, and rerun kernel-only CI once.

## HackerGadgets Radxa compatibility gate

- Official AIO2 rail IDs are BCM GPIO 27 (GPS), 16 (LoRa), 7 (SDR), and 23
  (internal USB). HackerGadgets documents that each rail is active-high and
  that internal USB must be enabled for the AC1200 module.
- Rex explicitly confirms the official `aiov2_ctl`/`pinctrl` path was written
  for Raspberry Pi and does not directly control Radxa pins.
- The pinned Radxa carrier DTS maps those standard header positions as:
  BCM27 / physical 13 -> gpio1 PC5, BCM16 / physical 36 -> gpio1 PA4,
  BCM7 / physical 26 -> gpio1 PB5, BCM23 / physical 16 -> gpio1 PA7.
- Supported implementation: a `gpio-leds` overlay owns those four Radxa lines,
  while a Radxa-model-guarded `/usr/local/bin/pinctrl` shim translates only the
  AIO2 controller's `get` and `set ... op dh|dl` calls. It refuses every other
  model and every other GPIO.
- Boot policy: SDR and internal USB on; GPS and LoRa off; Meshtastic daemon
  disabled until LoRa is explicitly powered.
- Runtime gate after flash: all four LED-class rails present, SDR/USB high,
  AC1200 enumerated with a network interface, AIO2 unit enabled, RTC readable.

## SHTF-box package gate

- No public GitHub release asset currently exists. Do not use an unpinned
  `latest` URL or build the package on the operator workstation.
- Diagnostic run `31360040321` proved the SHTF-box repository is private: the
  public image repository's scoped `GITHUB_TOKEN` received `Repository not
  found`, and the image repository has no cross-repository secret.
- Do not publish private source/binaries into the public image repository and
  do not store a broad personal token there. The image instead prepares
  `/srv/shtf-box/{packages,data,cache,models,maps,backups}` and
  `/etc/shtf-box/storage.env`; the private ARM64 package can be loaded after
  NVMe-root validation.

## Offline package configuration gate

- Gate: Debian image run `31413119902`, `Mount and modify image`.
- Contract hypotheses: package unavailable or dependency conflict. Evidence
  against: APT downloaded and unpacked the complete package set.
- Infrastructure hypothesis: maintainer scripts assume a booted/login system.
  Confirmed: `tar1090` failed because `/proc/cpuinfo` was absent; `pygpsclient`
  failed because `logname` returned no login account. `aiov2_ctl --add-apps`
  then correctly propagated APT's exit 100.
- Implementation/space hypotheses: no supporting error; overlays compiled,
  kernel/base downloads passed, and failure occurred during configuration.
- Minimal experiment: bind `/proc` and `/dev` into the arm64 chroot, do not bind
  `/run`, provide a temporary `logname` shim returning the existing UID-1000
  image user, remove it before publication, and rerun once.
