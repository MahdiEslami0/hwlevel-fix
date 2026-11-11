# Related fix: restoring IMEI with a matched engineering preloader+lk

This repo's Magisk module fixes `+ENVSIGERR` / "no signal" **assuming IMEI
already reports correctly**. On the device this was built for, IMEI itself
had to be restored first, separately, before the `hwlevel` override in
this repo made any difference. Documented here for anyone hitting both
problems after an `nvram`/`proinfo` wipe.

## Symptom this part addresses

After the wipe, IMEI showed blank/zero (`*#06#`, `service call
iphonesubinfo 1`) even with a correct, Luhn-valid IMEI written into NVRAM.
The device's **current, stock, retail `preloader`/`lk`** pair, combined
with the stock `md1img`, never let IMEI show — regardless of what was
written to NVRAM.

## What fixed it

Flashing a **matching engineering (`EF`/factory-stage) `preloader` + `lk`
pair** for this exact device/codename — while leaving `md1img` at its
*own, original, already-working* version — made IMEI report correctly
again on the next boot. No NVRAM/IMEI data was changed by this step; only
`preloader` and `lk_a` were overwritten.

Important specifics, found the hard way:

- The engineering package's own `md1img` (an older baseband build,
  `MOLY_LR13_R2_MP_V16_2_P14` in this case) is **not** compatible with a
  newer vendor/Android build on the same device — flashing it caused a
  modem crash loop (`MD WDT IRQ`, `MD exception stage 1/2` in `dmesg`).
  Only the engineering `preloader` + `lk` were used; the modem partition
  was restored from the device's own backup, not from the engineering
  package.
- The engineering package's `lk.img` and `preloader_viva.bin` are
  genuinely, validly signed (same signing chain as retail — they're a
  factory-stage build, not a forged/patched image), which is exactly why
  they boot at all on an SBC-locked chip where any *patched* `lk`/
  `preloader` byte reliably fails to boot (see
  [root-cause.md](root-cause.md) for what was tried and failed).
- Flashed with `mtkclient` in BROM mode:

  ```sh
  python mtk.py w preloader,lk_a "preloader_viva.bin,lk.img"
  ```

## Where to get a matching package

Xiaomi/ODM-distributed "Eng Rom (Engineering Firmware)" packages for
specific device codenames circulate on phone-repair forums and firmware
archive sites (search `"<device name>" eng rom engineering firmware`).
These are Xiaomi's own signed binaries — not redistributed from this repo.
Verify the package's declared MD5/version against what you're flashing,
and match the codename/model exactly (e.g. `viva` for the Redmi Note 11
Pro 4G) — a mismatched `preloader`/`lk` pair for a different device will
not pass the SBC signature check and may leave the phone unable to boot
until restored from a backup.

**Always take a full backup (`mtk.py r <partition> <out>` for `preloader`,
`lk_a`, `lk_b`, `md1img_a`, `md1img_b` at minimum) before flashing
anything**, and confirm you can restore it before experimenting further.

## Then apply this repo's fix

Once IMEI reports correctly, if the radio still won't power on
(`+ENVSIGERR: 1` in `adb logcat -b radio`), install the Magisk module from
the main [README](../README.md).
