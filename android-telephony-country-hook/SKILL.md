---
name: android-telephony-country-hook
description: Simulate Android telephony country and Locale values on an authorized rooted test device without changing app code. Use when Codex needs to make an app see another country, especially by hooking TelephonyManager.getSimCountryIso(), TelephonyManager.getNetworkCountryIso(), network operator values, or Locale.getDefault().country with Frida or LSPosed/Xposed; also use for clearing app country caches such as MMKV and validating Android country-resolution logs.
---

# Android Telephony Country Hook

## Scope

Use this skill only on an authorized rooted test device or emulator. Prefer a per-app scope. Avoid global LSPosed scope unless the user explicitly wants all scoped apps affected.

The common target is to make an app behave as an India user without modifying the app APK or source:

- `TelephonyManager.getSimCountryIso()` -> `"in"`
- `TelephonyManager.getNetworkCountryIso()` -> `"in"`
- optionally `TelephonyManager.getNetworkOperator()` -> `"40410"`
- optionally `TelephonyManager.getNetworkOperatorName()` -> `"Airtel"`
- `Locale.getDefault().country` -> `"IN"` by returning `Locale.forLanguageTag("en-IN")`

## Decide The Hook Path

Use **Frida** for fast single-process validation:

- No reboot required.
- Hook lasts only while the injected target process lives.
- Best for proving the exact methods and logs before building a persistent module.

Use **LSPosed/Xposed** for persistent scoped behavior:

- Requires Magisk with Zygisk enabled, an LSPosed-compatible Zygisk module, a reboot, and scope configuration.
- Works across target app restarts while the LSPosed module remains enabled.
- Best for repeated testing of the same app or multiple scoped apps.

## Inspect Before Hooking

First locate the app's actual country-resolution code:

```powershell
rg -n "getSimCountryIso|getNetworkCountryIso|Locale.getDefault|simCountryIso|networkCountryIso|indiaUser|country" app modules -S
```

Check whether the result is cached. If the app persists a resolved value, clear the cache or app data before validating:

```powershell
adb shell pm clear <package>
adb shell am force-stop <package>
```

For MMKV-backed fields such as `india_user` or `india_user_resolved`, stale cached values can make a correct hook appear broken.

## Frida Quick Hook

Install host tools and match `frida-server` to the host library version:

```powershell
python -m pip install --user frida-tools
python -c "import frida; print(frida.__version__)"
adb shell getprop ro.product.cpu.abi
```

Download the matching `frida-server-<version>-android-arm64.xz`, decompress it, push it, and run it as root:

```powershell
adb push frida-server /data/local/tmp/frida-server
adb shell su -c "chmod 755 /data/local/tmp/frida-server"
adb shell su -c "/data/local/tmp/frida-server -v"
```

Keep the server session open, then spawn the target app with a hook:

```javascript
Java.perform(function () {
  var TelephonyManager = Java.use("android.telephony.TelephonyManager");
  var Locale = Java.use("java.util.Locale");
  var indiaLocale = Locale.forLanguageTag("en-IN");

  function replaceStringMethod(name, value) {
    if (!TelephonyManager[name]) return;
    TelephonyManager[name].overloads.forEach(function (overload) {
      overload.implementation = function () { return value; };
    });
  }

  replaceStringMethod("getNetworkCountryIso", "in");
  replaceStringMethod("getSimCountryIso", "in");
  replaceStringMethod("getNetworkOperator", "40410");
  replaceStringMethod("getNetworkOperatorName", "Airtel");
  replaceStringMethod("getSimOperator", "40410");
  replaceStringMethod("getSimOperatorName", "Airtel");

  Locale.getDefault.overload().implementation = function () { return indiaLocale; };
  Locale.getDefault.overload("java.util.Locale$Category").implementation = function () { return indiaLocale; };
});
```

Run with:

```powershell
frida -U -f <package> -q --eternalize -l hook.js
```

If Frida reports `need Gadget to attach on jailed Android`, `frida-server` is not running as root. Start the server again and verify:

```powershell
frida-ps -U
adb shell su -c "pidof frida-server; ps -A | grep frida"
```

## LSPosed Persistent Hook

Use the bundled template when creating a scoped Xposed module:

```text
assets/xposed-module-template
```

The template contains a minimal Android app module with `assets/xposed_init` and a legacy Xposed entry class. It hooks:

- `TelephonyManager.getNetworkCountryIso()`
- `TelephonyManager.getSimCountryIso()`
- `Locale.getDefault()`
- `Locale.getDefault(Locale.Category)`

To reuse it, copy the template to a work directory, set `local.properties` with the local Android SDK path, build, and install:

```powershell
Copy-Item -Recurse "<skill>/assets/xposed-module-template" ".\telephony-country-xposed"
Set-Content ".\telephony-country-xposed\local.properties" "sdk.dir=D\:\\Android_SDK"
gradlew.bat -p .\telephony-country-xposed assembleDebug
adb install -r ".\telephony-country-xposed\app\build\outputs\apk\debug\app-debug.apk"
```

If there is no Gradle wrapper in the copied directory, run the root repo wrapper with `-p`, or use a local Gradle installation.

Install and enable an LSPosed-compatible Zygisk framework:

1. Confirm root and Android version:
   ```powershell
   adb shell su -c id
   adb shell getprop ro.build.version.release
   adb shell getprop ro.build.version.sdk
   adb shell su -c "magisk -V; magisk -v"
   ```
2. Use an LSPosed build compatible with the device's Android version. For Android 15, prefer a maintained Zygisk LSPosed/Vector build that declares SDK 35 support.
3. Install with Magisk:
   ```powershell
   adb push zygisk_lsposed.zip /data/local/tmp/zygisk_lsposed.zip
   adb shell su -c "magisk --install-module /data/local/tmp/zygisk_lsposed.zip"
   adb reboot
   ```
4. Verify `lspd` is running:
   ```powershell
   adb shell su -c "ps -A | grep -i lsp"
   ```
5. Install/open LSPosed Manager if needed, enable the hook module, and select the target package scope such as `com.flashy.light`.

If Zygisk is disabled, prefer enabling it in the Magisk app. Only edit `/data/adb/magisk.db` when the user accepts the risk; back it up first.

## Validate

Clear stale app data before a clean validation:

```powershell
adb logcat -c
adb shell pm clear <package>
adb shell am start -n <package>/<activity>
Start-Sleep -Seconds 7
adb logcat -d -s AdsSdkCoordinator TelephonyCountryHook LSPosed-Bridge AndroidRuntime
```

Look for all three signals:

```text
LSPosed-Bridge: Loading legacy module <hook-module-package>
TelephonyCountryHook: Locale default now en-IN, country=IN
AdsSdkCoordinator: SIM Country: in
AdsSdkCoordinator: Network Country: in
```

If app logs still show the old country:

- Confirm the target package is selected in LSPosed scope.
- Force-stop or clear the target app after changing scope or reinstalling the module.
- Confirm the module class logs `Hook installed for <package>`.
- Check whether the app uses cached values instead of re-running country resolution.
- Add temporary `Log.i` self-checks inside the hook module, then rebuild and reinstall.

## Notes From The Flashy Case

On the Pixel 6 test device, `resetprop gsm.operator.iso-country in` was not enough: the real registered network still came from modem service state (`MCC=460`, `MNC=00`, `CMCC`), so `TelephonyManager.networkCountryIso` stayed `cn`. Runtime hooks were required for `networkCountryIso`.

For `com.flashy.light`, MMKV persisted `india_user` and `india_user_resolved`; clearing app data was necessary before the first clean validation.
