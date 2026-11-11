# hwlevel-fix

A Magisk module that fixes "no signal" / radio stuck off on MediaTek-based
Xiaomi phones after an `nvram` / `proinfo` wipe, by overriding
`ro.boot.hwlevel` from `MP` to `P0` at boot.

## Tested device and exact state

| | |
|---|---|
| Device | Xiaomi Redmi Note 11 Pro 4G |
| Codename | `viva` |
| Model number | 2201116TG |
| SoC | MediaTek MT6781 (Helio G96) |
| ROM | MIUI V13.0.6.0.SGDMIXM, Android 12 |
| Baseband | `MOLY.LR13.R2.MP.V16.3.P52` / `...V16.3.P77` |
| Bootloader | Unlocked (`ro.boot.flash.locked=0`, `ro.boot.vbmeta.device_state=unlocked`) |
| Root | Magisk |
| `ro.boot.hwlevel` before fix | `MP` |

**How it broke:** a third-party repair tool formatted the wrong eMMC/UFS
partitions while attempting an unrelated repair, wiping `nvram`,
`proinfo`, `sec1` and `countrycode`. Everything else (`md1img`, `lk`,
`preloader`, `tee`, `boot`, `vendor`, `system`, `nvdata`, `nvcfg`,
`protect1`, `protect2`) was untouched and byte-identical to stock. This
module does **not** repair the wiped partitions themselves — it works
around the one specific consequence of that wipe described below.

**State immediately before applying this module** (the exact symptom this
module targets — confirm your device matches before trying it):

- `*#06#` / `service call iphonesubinfo 1` return a valid 15-digit IMEI
  (this had already been separately restored on the test device; this
  module assumes IMEI already works — if IMEI itself shows blank/zero,
  that is a *different* NV problem and this module alone will not fix it).
- `getprop gsm.sim.state` → `LOADED,ABSENT` (SIM is read correctly).
- `getprop vendor.mtk.md1.status` → `ready` (modem subsystem itself is up,
  not crashed).
- `dumpsys telephony.registry` → `mVoiceRegState=3(POWER_OFF)`,
  `mRadioPowerState=0`, for both SIM slots, permanently — toggling
  airplane mode on/off, or rebooting, never changes this.
- `getprop ro.boot.hwlevel` → `MP`.
- `adb logcat -b radio`, triggered by any radio-power request (e.g.
  toggling airplane mode), shows this exact exchange on a loop, forever:

  ```
  AT> AT+EFUN=1
  AT< ERROR
  AT< +ENVSIGERR: 1
  RmcOemUrcHandler: recovery mode because of not factory mode:+ENVSIGERR: 1
  ```

**State immediately after installing this module and rebooting** (same
device, same SIM, nothing else changed):

- `getprop ro.boot.hwlevel` → `P0`.
- `adb logcat -b radio` on the next radio-power request shows `AT+EFUN=1`
  followed by `OK` instead of `ERROR` / `+ENVSIGERR: 1`.
- `dumpsys telephony.registry` moves `mRadioPowerState` away from `0` and
  `mVoiceRegState`/`mDataRegState` out of `POWER_OFF`; the device attaches
  to the carrier network and shows signal bars normally.
- No other visible change: same IMEI, same installed apps/data, no
  partitions were flashed.

The same root-cause pattern (`ro.boot.hwlevel=MP` refusing to run without
factory-signed NV data, after that data was wiped) has been reported on
other Xiaomi/MediaTek devices too (see [Prior art](#prior-art)), but this
exact module has only been run end-to-end on the device/state above — read
[Will this work on my device?](#will-this-work-on-my-device) before
relying on it on anything else.

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
