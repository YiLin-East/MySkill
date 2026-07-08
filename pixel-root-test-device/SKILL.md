---
name: pixel-root-test-device
description: Root an authorized Google Pixel test device with Magisk from official factory images. Use when the user asks Codex to root a Pixel phone, prepare a Pixel test device with root, patch and flash Pixel boot images, verify Magisk root, or recover/diagnose a Pixel root attempt. Requires explicit user ownership/authorization and device-side confirmation for bootloader unlock.
---

# Pixel Root Test Device

## Scope And Safety

Use this skill only for a Pixel device the user owns or is authorized to modify. Do not help bypass carrier/OEM unlock restrictions, theft protections, account locks, or device-side confirmation screens.

Treat these as hard stops:

- Before `fastboot flashing unlock`, state that it wipes user data and wait for explicit user readiness if the user has not already confirmed.
- Do not use third-party boot images or patched images. Download stock firmware only from Google official factory image URLs.
- Match the factory image exactly to the device codename and current build fingerprint before patching or flashing.
- If multiple adb/fastboot devices are present, always specify the serial.
- Keep stock `boot.img` and patched boot image on the host for recovery.

## Workflow

1. Confirm tools and device state.
2. Identify device codename, build fingerprint, bootloader state, active slot, and unlock ability.
3. Download the matching Google factory image and verify SHA-256.
4. Extract `boot.img` from the inner image zip.
5. Patch `boot.img` with the official Magisk APK.
6. Unlock bootloader with user confirmation on device.
7. Flash the patched boot image to the active boot slot.
8. Install Magisk APK, grant Shell superuser permission, and verify root.

## Preflight Commands

On Windows PowerShell, avoid `&&`; run commands on separate lines or with PowerShell syntax.

```powershell
adb devices -l
fastboot --version
adb -s <serial> shell getprop ro.product.device
adb -s <serial> shell getprop ro.product.model
adb -s <serial> shell getprop ro.build.fingerprint
adb -s <serial> shell getprop ro.build.id
adb -s <serial> shell getprop ro.boot.flash.locked
adb -s <serial> shell getprop ro.boot.vbmeta.device_state
adb -s <serial> shell getprop ro.boot.verifiedbootstate
adb -s <serial> shell su -c id
```

Expected before root:

- `su` is missing or inaccessible.
- `ro.boot.flash.locked` is `1` or bootloader state is `locked`.

Reboot to bootloader and check:

```powershell
adb -s <serial> reboot bootloader
fastboot devices
fastboot getvar product 2>&1
fastboot getvar current-slot 2>&1
fastboot getvar unlocked 2>&1
fastboot flashing get_unlock_ability 2>&1
```

Proceed only if `product` matches the codename and `get_unlock_ability: 1`. If `get_unlock_ability: 0`, tell the user OEM unlocking is disabled or unavailable and stop.

## Factory Image Handling

Use the Google factory image page and `dl.google.com` links. Verify the URL with a HEAD request before download.

```powershell
$url = '<official-factory-image-url>'
Invoke-WebRequest -UseBasicParsing -Method Head -Uri $url
curl.exe -L --fail --retry 3 -C - -o work\pixel-root\<factory>.zip $url
Get-FileHash -Algorithm SHA256 work\pixel-root\<factory>.zip
tar -tf work\pixel-root\<factory>.zip
```

Factory zips normally contain an inner `image-<codename>-<build>.zip`. Extract only what is needed:

```powershell
tar -xf work\pixel-root\<factory>.zip -C work\pixel-root\factory
tar -tf work\pixel-root\factory\<folder>\image-<codename>-<build>.zip
tar -xf work\pixel-root\factory\<folder>\image-<codename>-<build>.zip -C work\pixel-root boot.img
Get-FileHash -Algorithm SHA256 work\pixel-root\boot.img
```

For Pixel 6 / Pixel 6 Pro generation, patch `boot.img`. For devices with `init_boot.img`, patch `init_boot.img` instead; confirm with current Magisk instructions and the image contents.

## Magisk Patch Path

Prefer the official Magisk APK release from the Magisk project. If GitHub API is rate-limited, use the release page or exact release asset URL.

Magisk APKs contain `assets/boot_patch.sh` and per-ABI native libraries. To patch on the device without existing root:

1. Extract arm64 files from the APK on the host.
2. Rename libraries as expected by `boot_patch.sh`.
3. Push them and the stock boot image to `/data/local/tmp/magisk_patch`.
4. Run the patch script from adb shell.

Required file mapping:

```text
assets/boot_patch.sh -> boot_patch.sh
assets/util_functions.sh -> util_functions.sh
assets/stub.apk -> stub.apk
lib/arm64-v8a/libmagiskboot.so -> magiskboot
lib/arm64-v8a/libmagiskinit.so -> magiskinit
lib/arm64-v8a/libmagiskpolicy.so -> magiskpolicy
lib/arm64-v8a/libmagisk.so -> magisk
lib/arm64-v8a/libinit-ld.so -> init-ld
lib/arm64-v8a/libbusybox.so -> busybox
```

Patch command:

```powershell
adb -s <serial> shell 'rm -rf /data/local/tmp/magisk_patch && mkdir -p /data/local/tmp/magisk_patch'
adb -s <serial> push work\pixel-root\patch-pc\* /data/local/tmp/magisk_patch/
adb -s <serial> shell 'cd /data/local/tmp/magisk_patch && chmod 755 boot_patch.sh magiskboot magiskinit magiskpolicy magisk init-ld busybox && BOOTMODE=true KEEPVERITY=true KEEPFORCEENCRYPT=true PATCHVBMETAFLAG=false sh ./boot_patch.sh ./boot.img && ls -l'
adb -s <serial> pull /data/local/tmp/magisk_patch/new-boot.img work\pixel-root\magisk_patched_boot.img
Get-FileHash -Algorithm SHA256 work\pixel-root\magisk_patched_boot.img
```

Some optional patch attempts may print `Failed to patch` while the script still repacks `new-boot.img`. Verify by unpacking the patched image with `magiskboot`; `magiskboot cpio ramdisk.cpio test` returning `1` indicates a Magisk-patched ramdisk.

## Unlock And Flash

Before this command, warn again that unlocking wipes data. The user must confirm on the device with the volume/power keys.

```powershell
fastboot flashing unlock
```

After wipe, adb authorization is reset. Wait for the user to finish setup, enable USB debugging, and authorize the host again. Then flash:

```powershell
adb devices -l
adb -s <serial> reboot bootloader
fastboot devices
fastboot getvar current-slot 2>&1
fastboot getvar unlocked 2>&1
fastboot flash boot work\pixel-root\magisk_patched_boot.img
fastboot reboot
```

If the target image is `init_boot.img`, flash `init_boot` instead of `boot`.

## Finalization And Verification

Install Magisk after boot:

```powershell
adb -s <serial> wait-for-device
adb -s <serial> shell getprop sys.boot_completed
adb -s <serial> install -r work\pixel-root\Magisk-<version>.apk
adb -s <serial> shell su -v
adb -s <serial> shell su -V
adb -s <serial> shell su -c id
```

If `su -v` works but `su -c id` says `Permission denied`, open Magisk, go to **Superuser**, and enable `[SharedUID] Shell / com.android.shell`. Then verify again.

Root is confirmed only when:

```text
uid=0(root) gid=0(root) ... context=u:r:magisk:s0
```

Also record:

```powershell
adb -s <serial> shell getprop ro.boot.slot_suffix
adb -s <serial> shell getprop ro.boot.flash.locked
adb -s <serial> shell getprop ro.boot.verifiedbootstate
```

An unlocked rooted Pixel normally reports `ro.boot.flash.locked=0` and `verifiedbootstate=orange`.

## Recovery Notes

If boot fails after flashing patched boot:

1. Enter bootloader manually with volume down + power.
2. Flash the saved stock `boot.img` back to the same partition.
3. Reboot and reassess the build/image match.

```powershell
fastboot flash boot work\pixel-root\boot.img
fastboot reboot
```

Do not relock the bootloader while any non-stock partition is flashed. Relocking with modified boot images can brick or wipe the device.
