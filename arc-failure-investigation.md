# ARC: Radxa CM5 uConsole black screen

## Evidence-first operating protocol

1. Capture exact gate, command, revision, inputs, and durable log before edits.
2. Record competing contract, configuration, infrastructure, data/state, and
   implementation hypotheses.
3. Run smallest read-only experiment that separates leading hypotheses.
4. Apply only fix supported by evidence; define expected pass signal first.
5. Run narrow local validation, then failed CI gate once.
6. After any repeated failure, update this ledger and inspect preserved evidence;
   never start another full run without new diagnostic evidence or a relevant fix.
7. Report state as verified, failed, or unknown. Never claim flashed, installed,
   or validated without corresponding artifact, readback, or target runtime test.
8. Never execute target package/configuration scripts on operator host
   `bugoutbox` (`192.168.0.10`). Offline target execution is limited to CI chroot;
   hardware configuration runs only after positive target identity verification.

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

### Follow-up run

- Gate: Debian image run `31458347178`, before the chroot package phase.
- Confirmed: root partition growth, `e2fsck`, `resize2fs`, mounts, and the pinned
  key SHA-256 check passed. The step exited immediately after GPG created its
  trust database, before logging a fingerprint or installing packages.
- Key-content hypothesis: ruled out locally; the downloaded key has the pinned
  SHA-256 and fingerprint `5799BD7F376D1011C510B036B40C8F551C4AB897`.
- Leading gate hypothesis: the combined GPG-to-awk command substitution failed
  or produced a runner-specific value, but the workflow did not expose which.
- Minimal experiment: write `gpg --show-keys --with-colons` to a temporary file,
  extract and log the fingerprint separately, then apply the same exact match.

### Fingerprint experiment result

- Gate: Debian image run `31458828747`, same pre-chroot key-validation phase.
- Confirmed cause: `gpg --no-options` did not create the default runner GPG home;
  it exited 2 with `Fatal: /home/runner/.gnupg: directory does not exist`.
- Minimal fix: create a mode-0700 GPG home under `$RUNNER_TEMP` and pass it with
  `--homedir`. It is runner-only, never copied into the target image.

### Repository-component gate result

- Gate: Debian image run `31459036162`, immediately after key validation.
- Confirmed: isolated GPG home worked and the exact expected fingerprint was
  logged. The following `non-free-firmware` source assertion exited 1.
- Root cause: Radxa rsdk-b3's Bookworm source configuration does not include the
  Debian 12 `non-free-firmware` component required by `firmware-mediatek`.
- Minimal fix: add component-only Bookworm, Bookworm updates, and security source
  lines, avoiding duplicate `main` entries, then keep the assertion.

### Source assertion follow-up

- Gate: Debian image run `31459394194`, within 70 ms after the valid fingerprint.
- The broad recursive source assertion still exited 1 without identifying which
  preceding quiet command completed.
- Minimal diagnostic: emit stage markers, assert the exact firmware source file
  written by this workflow, and search that file directly. This distinguishes
  key install, AK-Rex source write, firmware source write, and assertion failures.

### Post-repository identity gate

- Gate: Debian image run `31459931670`, after `Repository gate: complete`.
- Repository key/source hypotheses are ruled out. The base root listing shows an
  empty `/home`; the next strict operation rejects an absent UID-1000 user.
- Minimal fix: use the image's UID-1000 identity when present, otherwise `root`
  solely for the temporary `logname` compatibility shim. Log the choice and
  remove the shim before publishing; do not create or change credentials.

### Offline maintainer-script result

- Gate: Debian image run `31461624127`, HackerGadgets application configuration.
- `pygpsclient` still called the real `/usr/bin/logname`; `/usr/local/sbin` is not
  in dpkg maintainer scripts' PATH. It then tried `usermod` with an empty user.
- `tar1090` first installed readsb, but the policy-blocked service could not
  create `/run/readsb/aircraft.json` without target SDR hardware. Its following
  tar1090 installer therefore exited 1.
- Minimal fix: use temporary image-local dpkg diversions for `/usr/bin/logname`
  and `/usr/bin/systemctl`, seed a valid temporary readsb JSON file, configure
  packages, then remove the seed and restore both original binaries. `/run` is
  never bound from the runner, so target scripts cannot contact host systemd.

### Kernel artifact availability

- Gate: Debian image run `31463553741`, before base-image download.
- Confirmed infrastructure cause: kernel artifact `9051925615` expired at the
  configured one-day retention boundary. GitHub API reports `expired: true`;
  no image or package command ran.
- Minimal fix: rebuild the same pinned kernel in the current workflow and retain
  kernel artifacts for seven days so diagnostic image iterations remain usable.

### PyGPSClient virtual environment

- Gate: full kernel+Debian run `31463963934`, PyGPSClient post-installation.
- Confirmed: fresh kernel passed; tar1090/readsb completed with the offline JSON
  seed; `logname` resolved to the selected image identity.
- Root cause: PyGPSClient creates a Python virtual environment but its package
  does not depend on `python3-venv`; `ensurepip` was unavailable.
- Minimal fix: install and assert Debian's `python3-venv` before invoking the
  official HackerGadgets application installer.

### PyGPSClient Raspberry boot-path assumption

- Gate: Debian image run `31467200704`, final PyGPSClient post-install step.
- Confirmed: virtual environment and all Python dependencies installed. The
  package then failed only because it unconditionally edits Raspberry Pi path
  `/boot/firmware/cmdline.txt` to remove `console=serial0,115200`.
- Radxa uses `/boot/extlinux/extlinux.conf`; that Raspberry token/path is absent.
- Minimal fix: provide an empty temporary Pi compatibility file during package
  configuration, remove it afterward, and retain assertions on Radxa extlinux.

### Selected-package maintainer-script audit

- Audited all maintainer scripts for `hackergadgets-uconsole-aio-board`,
  `meshtastic-mui`, `sdrpp-brown`, `tar1090`, `pygpsclient`, and `pinctrl`.
- No further fatal offline assumptions were found. Raspberry config mutations in
  the AIO and Meshtastic packages are conditional and exit successfully when
  Radxa's config paths are absent.
- One latent root-only-image issue was found: PyGPSClient's launcher points to
  `/home/root`, which is only a temporary compatibility link. Replace it with
  `/root/.pygpsclient/bin/pygpsclient` and assert the launcher is executable.

### SHTF storage-file assembly

- Gate: Debian image run `31468811243`, after every selected package configured.
- Confirmed: HackerGadgets AIO, tar1090/readsb, PyGPSClient, Meshtastic MUI,
  meshtasticd, and SDR++ all reached installed state.
- Root cause: the workflow's `SHTF_EOF` terminator had two extra spaces, so Bash
  consumed the remaining cleanup block as heredoc content and exited 1.
- Minimal fix: align the terminator with the YAML-stripped shell column. Keep
  `actionlint`, `shellcheck`, static package assertions, and artifact inspection.

### Silent post-package failure

- Gate: Debian image run `31470416502`, after all upstream packages configured
  and the corrected SHTF heredoc executed.
- Package/maintainer hypotheses are ruled out. Remaining candidates are cleanup
  restoration, free-space threshold, package-state loop, or static boot/files.
- A clean Debian Bookworm container reproduces both dpkg diversions successfully.
  However, target logs show real systemctl already handled the chroot safely, so
  its diversion is unnecessary state and is removed.
- Minimal diagnostic: retain only the required logname diversion; add an ERR
  trap, named package assertions, cleanup markers, and the exact free-space value.
  Do not rerun again without an exact failing command.

### PyGPSClient launcher assertion

- Gate: Debian image run `31514590684`, first static-file assertion group.
- Confirmed: chroot cleanup completed, every named package is `ii`, and root has
  6,529,884 KiB free. Exact failure: `/usr/local/bin/pygpsclient` not executable.
- Root cause: the venv was created through `/home/root -> /root`, so generated
  shebangs embed `/home/root/.pygpsclient/bin/python3`. Removing that compatibility
  link breaks the launcher; retargeting only the outer symlink cannot fix shebangs.
- Minimal fix: retain and assert `/home/root -> /root`, which preserves the path
  contract of the upstream installer without changing root's passwd home field.

### PyGPSClient launcher contract correction

- Gate: Debian image run `31516734551`, commit `f7bf0a8`, static-file assertions.
- Exact failure repeated: `sudo test -x ./mnt/root/usr/local/bin/pygpsclient`.
- Contract hypothesis confirmed by pinned upstream installer source: it creates
  `/home/<user>/.pygpsclient/bin/pygpsclient` and edits interactive shell PATH;
  it never creates `/usr/local/bin/pygpsclient`.
- Previous shebang-only root cause was incomplete. Retaining `/home/root -> /root`
  preserves venv shebangs but cannot create a missing system launcher.
- Infrastructure, package-state, and space hypotheses ruled out: package was
  `ii`, pip install completed, cleanup completed, and 6,529,884 KiB remained.
- Smallest discriminating experiment: source search found no launcher creation;
  only workflow assertion referenced `/usr/local/bin/pygpsclient`.
- Minimal fix: create an absolute target-side symlink from `/usr/local/bin/pygpsclient`
  to the selected user's venv executable. Assert link target and venv executable
  separately without invoking ARM target code on the runner. For root-only images,
  inspect physical mounted path `/root/.pygpsclient/...`; host-side traversal of
  image link `/home/root -> /root` would otherwise escape into runner `/root`.

### Physical boot gate: solid activity LED and black internal panel

- Gate: first normal boot on 2026-08-12 after flashing Debian artifact from run
  `31518782492`, commit `fa6f3ac`, image SHA-256
  `24958f58eb8130b6efb06b86dd0c546b7e2e8a229bbacbb9167d029e2fed6738`.
- Flash transport and media corruption are ruled out: 12 GiB eMMC readback was
  byte-identical to the source image. MASKROM USB disappeared after normal boot,
  but the internal screen stayed black and the CM5 activity LED stayed solid.
  No new DHCP/mDNS neighbor appeared. The supplied MAC `60:cf:84:62:f4:b3`
  was positively identified as the workstation's `eno1`, so it is excluded.
- Leading hypotheses: bootloader/kernel does not reach userspace; AIO2 or 2 TB
  NVMe causes power/short instability; Linux boots but lacks display and network
  configuration. Panel-only failure is weakened by Radxa's documented activity
  LED behavior: blue should blink after Linux enters the system.
- Smallest discriminating experiments, in order: observe HDMI or serial output;
  attach AIO2 Ethernet and probe for a new DHCP identity; then cold-boot once
  with NVMe removed while leaving eMMC unchanged. Do not reflash until one probe
  implicates image/bootloader state.
- NVMe-isolation result: removing the 2 TB NVMe did not change the solid blue
  LED, black panel, absent normal-mode USB, or absent LAN identity. NVMe media
  and PCIe enumeration are therefore not the primary boot blocker.
- Next discriminator: cold-boot without the AIO2/RJ45 expansion board. The
  HackerGadgets product warning says an incorrectly oriented expansion ribbon
  can prevent boot and must not be powered or charged; a 2026 Radxa CM5/AIO2
  report also reproduced boot failure only while the AIO2 was installed.

### Radxa boot layout and CWU50 backlight contract

- Root boot failure cause confirmed: image assembly mounted rsdk-b3's p2 `efi`
  filesystem at `/boot`, but image fstab and upstream extlinux contract mount it
  at `/boot/efi` and keep kernel/extlinux on rootfs `/boot`. Generated extlinux
  therefore omitted `fdtdir`; U-Boot had no CM5 base DTB and never mounted root.
- Diagnostic boot without overlays produced the same failure, while restoring
  rootfs `/boot`, `/boot/vmlinuz-*`, and `fdtdir /usr/lib/linux-image-*` caused
  Linux activity and first-boot root expansion. Full corrected-image eMMC
  readback matched its source SHA-256 byte-for-byte.
- Display gate then failed with a dark internal panel. Captured target journal
  proved kernel/userspace boot and showed `panel-cwu50` detecting the new panel,
  reaching `devm_of_find_backlight`, then leaving MIPI DSI deferred forever.
- Composed DTB contains a valid `ocp8178-backlight` node and panel phandle, but
  running kernel config says `# CONFIG_BACKLIGHT_OCP8178 is not set`. This is
  the exact missing driver. Minimal fix: build it as a module, assert the config,
  retain rootfs boot layout, rebuild image, then verify live panel/DRM state.

### Corrected-image CI assertion failure

- Run `31763602529` built the corrected kernel successfully; independent
  artifact inspection found `CONFIG_BACKLIGHT_OCP8178=m` and
  `drivers/video/backlight/ocp8178_bl.ko`.
- Debian assembly reached every package assertion, then rejected the first
  overlay (`axp20x.dtbo`). The image-content hypothesis was weakened because
  the generated line begins with exactly one separator:
  `fdtoverlays /boot/dtbo/axp20x.dtbo ...`.
- Root cause: the assertion regex contained both the separator before `.*` and
  another literal separator after it, so the first token required two spaces.
  The same regex passed every later overlay. A minimal replay against the
  captured target extlinux file reproduced that exact first-token-only failure.
- Correction: parse the `fdtoverlays` record as whitespace-delimited fields
  with `awk` and require each expected path as an exact token. Reuse the
  successful kernel artifact for the image-only rerun.
