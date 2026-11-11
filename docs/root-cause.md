# Root cause and investigation notes

Background for anyone hitting the same wall. This documents what was tried
on a Redmi Note 11 Pro 4G ("viva", MT6781/Helio G96, MIUI 13, Android 12,
bootloader unlocked, Magisk-rooted) whose `nvram`/`proinfo`/`sec1`/
`countrycode` partitions were wiped by a third-party repair tool.

## Symptom recap

- IMEI could be made to show correctly again (preloader/lk swap from a
  matching engineering firmware package restored NVRAM-derived state —
  separate issue from this one).
- Cellular signal never came back. `adb logcat -b radio` showed, on every
  attempt to power the radio:

  ```
  AT> AT+EFUN=1
  AT< ERROR
  AT< +ENVSIGERR: 1
  RmcOemUrcHandler: recovery mode because of not factory mode:+ENVSIGERR: 1
  ```

## What was ruled out, and how

1. **Patching `lk`'s secure-boot policy table.** `lk.img` contains, per
   partition, a 4-byte policy group
   `[sbc_disabled_locked, sbc_disabled_unlocked, sbc_enabled_locked,
   sbc_enabled_unlocked]`. Clearing bit 1 of the `md1img` entry's
   `sbc_enabled_unlocked` byte (`02` → `00`) is a documented technique on
   at least one other Xiaomi/MediaTek device (see
   [Prior art](../README.md#prior-art) in the main README — the "biloba"
   writeup) that disables LK's signature check on the modem partition.

   **Result on this device: total boot failure (phone would not power on
   at all) — not a bootloop, a hard failure before anything else loaded.**
   Restored from backup, confirmed working again. This was tested twice,
   including once in isolation (LK byte changed, modem untouched). Any
   single-byte modification to a live, SBC-protected `lk.img` on this
   device's preloader is rejected outright. The technique that worked for
   another device's preloader does not transfer here — "SBC enforced, no
   exceptions" was independently confirmed (this makes 4 separate
   confirmations across this investigation, including earlier unrelated
   attempts). **Do not patch `lk.img` on this device.**

2. **Patching the `md1img` (modem) binary directly** — multiple attempts:
   - A MIPS16e function physically near relevant debug strings
     (`custom_nvram_check_imei_skip_flag`, `"it's MP, can not skip!"`,
     `"now flag nv is 0x1234"`) was patched to unconditionally return
     success (`li v0,0; jrc ra; nop`, same pattern as the prior-art
     project). Flashing it alone (`lk` untouched) caused a **modem
     bootloop** (AP boots fine, modem subsystem crashes repeatedly).
     Restored from backup.
   - Cross-checking with a real disassembler (Ghidra, `MIPS:LE:32:16e`
     language) afterwards showed this exact function has **zero callers**
     anywhere in the 150MB firmware image — neither a direct `jal` nor a
     stored function pointer. The debug strings were a red herring; the
     function is most likely unreachable/dead code in this specific build,
     and the crash came from disturbing something adjacent, not from the
     "logical" patch itself.
   - The actual string reference chain for `custom_nvram_check_signed_
     critical_data` and `+ENVSIGERR` was then traced directly (not via
     nearby strings) using Ghidra. It leads into a large, generic
     NV-item read/verify routine that's shared across many unrelated NV
     operations, not an isolated, single-purpose check — meaning any
     1:1 byte patch risks breaking unrelated functionality in
     unpredictable ways. This was deemed too risky to patch blind.

3. **Writing an NV flag item directly (`LID 0xf265`, `0xe42d`
   candidates).** Neither candidate LID exists as a standalone record in
   `nvdata`/`protect1`/`protect2` after the wipe, in either the simple
   `LDI`-container format or the alternate default-table format used on a
   different device's firmware. Not pursued further — same risk profile as
   above without a confirmed, safe target.

4. **MediaTek's `mdlog`/`emdlogger` modem trace logger**, which could have
   shown the exact failing check in real time instead of guessing: the
   required kernel device node (`/dev/emd_cfifo1`) is not present on this
   build, so this channel wasn't available here.

## What actually worked

None of the binary-level approaches above were both safe and effective on
this device. The fix that worked operates one level up, in Android
userspace: the modem/RIL stack reads `ro.boot.hwlevel` through the normal
Android property mechanism at init time. Overriding that property (not the
boot-chain value it's normally derived from) via `resetprop
ro.boot.hwlevel P0` in a Magisk `post-fs-data.sh`, early enough to run
before the modem stack initializes, is enough for the signed-critical-data
gate to take its relaxed "engineering" path. See the main
[README](../README.md) for the module itself.

This is **not** a fix for the original wipe — `nvram`/`proinfo`/`sec1`/
`countrycode` are still empty/default. It's a fix for the specific
consequence (`hwlevel=MP` refusing to run without factory-signed data) that
happens to be enough to restore normal radio function in practice.

## Why not just re-sign things properly?

The signed-critical-data check validates against Xiaomi's real factory
signing infrastructure (SLA — Serial Link Authentication / per-device
challenge-response, plus CSSD-style signed NV blobs whose trust root is a
hardcoded Xiaomi RSA key inside the modem binary). There is no way to
forge data that validates against that key without the private key itself;
replacing the embedded public key (`--keyswap`-style) breaks the chain of
trust the same way as any other `md1img`/`lk` tamper and was tested earlier
in this investigation with the same "crash or total failure" outcome as
the other binary patches above. The userspace property override sidesteps
needing a valid signature at all, by making the firmware believe it's
running in a context where one was never required.
