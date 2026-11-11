# hwlevel-fix

A Magisk module that fixes "no signal" / radio stuck off on MediaTek-based
Xiaomi phones after an `nvram` / `proinfo` wipe, by overriding
`ro.boot.hwlevel` from `MP` to `P0` at boot.

Confirmed on: **Redmi Note 11 Pro 4G ("viva"), MT6781/Helio G96, MIUI
13 (Android 12), unlocked bootloader, rooted with Magisk.** The same
root cause pattern (`ro.boot.hwlevel=MP` + wiped NVRAM) has been reported
on other Xiaomi MediaTek devices too (see [Prior art](#prior-art)), but the
fix has only been tested end-to-end on the device above — read
[Will this work on my device?](#will-this-work-on-my-device) before relying
on it.

## Symptom

- The phone was repaired / had its `nvram`, `proinfo`, `sec1` or
  `countrycode` partitions wiped (commonly by a repair tool that formatted
  the wrong partition, or by a bad flash).
- IMEI may or may not show up in `*#06#` / Settings, but there is **no
  cellular signal at all**, and it never recovers no matter how many times
  you toggle airplane mode or reboot.
- `adb logcat -b radio` shows the modem rejecting every radio-power
  request:

  ```
  AT> AT+EFUN=1
  AT< ERROR
  AT< +ENVSIGERR: 1
  RmcOemUrcHandler: recovery mode because of not factory mode:+ENVSIGERR: 1
  ```

- `getprop ro.boot.hwlevel` reports `MP` (mass production / retail).

## Root cause

Xiaomi's modem firmware (MOLY baseband) has a "signed critical data" gate:
before it allows the radio to power on (`AT+EFUN=1`), it checks
`ro.boot.hwlevel`. On `MP` (retail) builds, this gate is enforced and
requires NV data that is cryptographically signed by Xiaomi's factory
infrastructure (SLA). If that signed data is missing — e.g. because
`nvram`/`proinfo` got wiped — the modem refuses to turn the radio on and
returns `+ENVSIGERR: 1` forever, even though the rest of the phone (IMEI,
Android, Wi-Fi, etc.) can work fine.

On `P0` (engineering) builds this same gate is relaxed, because engineering
units are expected to run without the full factory-signed NV set.

`ro.boot.hwlevel` is normally burned into the boot chain and cannot be
changed there (the bootloader's secure-boot chip fuses enforce it
regardless of the Android-level unlock state — patching `lk`/`preloader`/
`md1img` directly to change it, or to bypass the signed-data check inside
the modem binary, reliably **bricks the boot chain or crashes the modem**;
this was tested extensively and is not a viable path on this chip).

The practical fix instead targets the **Android property**, not the
boot-chain value: the modem/RIL stack reads `ro.boot.hwlevel` via the
normal Android property service at init time, so overriding that property
early enough (via Magisk's `resetprop`, in `post-fs-data`, before the modem
stack starts) is enough to make the signed-data gate take the relaxed `P0`
path — without touching any signed partition.

## What this module does

On every boot, in `post-fs-data` (i.e. before the modem/RIL stack starts):

```sh
resetprop ro.boot.hwlevel P0
```

That's the entire fix. No partitions are flashed, no binaries are patched,
nothing irreversible happens. Removing the module (or unrooting) simply
reverts to stock behavior.

## Install

**Option A — Magisk app**

1. Download `hwlevel_p0_override.zip` from [Releases](../../releases) (or
   build it yourself: `./build.sh`).
2. Magisk app → Modules → Install from storage → pick the zip.
3. Reboot.

**Option B — adb, no Magisk app needed**

```sh
git clone <this-repo-url>
cd hwlevel-fix
./install.sh      # pushes the module straight into /data/adb/modules
adb reboot
```

Requires a rooted device already reachable via `adb shell su -c ...`.

## Verify it worked

```sh
adb shell getprop ro.boot.hwlevel        # should read P0 after reboot
adb logcat -b radio | grep EFUN          # AT+EFUN=1 should now return OK, not ENVSIGERR
```

## Persistence — what survives what

| Event | Does the fix survive? |
|---|---|
| Normal reboot / power cycle | ✅ Yes — Magisk re-runs `post-fs-data.sh` every boot |
| Settings → "Erase all data" / factory reset | ❌ No — wipes `/data`, which includes `/data/adb/modules` |
| Unrooting / uninstalling Magisk | ❌ No — the override is applied by Magisk itself |
| Flashing a new ROM (replaces `vendor`/`boot`) | ❌ No — by definition, flashing replaces whatever was there, on **any** phone |

There is no userspace trick that survives a full ROM flash — flashing
*is* overwriting the partitions involved, on every Android device, not
just this one. If you do a factory reset or reflash, just re-root and
re-run `./install.sh` (or reflash the zip) — it takes under a minute.

## Will this work on my device?

Maybe, but verify the premise first — **don't flash anything blind**:

1. Confirm the symptom matches: `+ENVSIGERR: 1` in `adb logcat -b radio`
   when toggling airplane mode, and `getprop ro.boot.hwlevel` = `MP`.
2. This module only resets one property; it's low-risk to *try*, but it is
   only useful if your actual blocker is this specific signed-data gate.
   If your IMEI itself is also missing/zero, that's a separate problem
   (NV/IMEI data, not this gate) and this module won't fix it by itself.
3. MediaTek SoC + Xiaomi/MIUI "MOLY" baseband is the relevant combination.
   Non-MediaTek (Qualcomm) Xiaomi phones do not have this specific gate.

## Prior art

- [killindodo/redmi-note9-nvram-restore](https://github.com/killindodo/redmi-note9-nvram-restore) —
  documents the same `hwlevel=MP` vs `P0` distinction on the Redmi Note 9
  (Helio G85) and was the direct inspiration for this fix.
- [maoist2009/aresnv](https://github.com/maoist2009/aresnv) — a related,
  deeper writeup of Xiaomi's MTK NVRAM/IMEI signing scheme on a different
  device (Redmi K40 Game Enhanced Edition).

See [`docs/root-cause.md`](docs/root-cause.md) for the full investigation
notes (what was tried, what failed, and why direct binary/partition
patching is not a safe path on this chip).

## License

MIT — see [LICENSE](LICENSE).
