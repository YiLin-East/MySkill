package com.flashy.test.telephonycountry;

import android.util.Log;
import java.util.Locale;
import de.robv.android.xposed.IXposedHookLoadPackage;
import de.robv.android.xposed.XC_MethodReplacement;
import de.robv.android.xposed.XposedBridge;
import de.robv.android.xposed.XposedHelpers;
import de.robv.android.xposed.callbacks.XC_LoadPackage;

public final class TelephonyCountryHook implements IXposedHookLoadPackage {
    private static final String TAG = "TelephonyCountryHook";
    private static final String INDIA_COUNTRY_ISO = "in";
    private static final Locale INDIA_LOCALE = Locale.forLanguageTag("en-IN");

    @Override
    public void handleLoadPackage(XC_LoadPackage.LoadPackageParam loadPackageParam) {
        try {
            Log.i(TAG, "handleLoadPackage: " + loadPackageParam.packageName);
            XposedHelpers.findAndHookMethod(
                    "android.telephony.TelephonyManager",
                    loadPackageParam.classLoader,
                    "getNetworkCountryIso",
                    XC_MethodReplacement.returnConstant(INDIA_COUNTRY_ISO)
            );
            XposedHelpers.findAndHookMethod(
                    "android.telephony.TelephonyManager",
                    loadPackageParam.classLoader,
                    "getSimCountryIso",
                    XC_MethodReplacement.returnConstant(INDIA_COUNTRY_ISO)
            );
            XposedHelpers.findAndHookMethod(
                    "java.util.Locale",
                    null,
                    "getDefault",
                    XC_MethodReplacement.returnConstant(INDIA_LOCALE)
            );
            XposedHelpers.findAndHookMethod(
                    "java.util.Locale",
                    null,
                    "getDefault",
                    Locale.Category.class,
                    XC_MethodReplacement.returnConstant(INDIA_LOCALE)
            );
            XposedBridge.log("TelephonyCountryHook active for " + loadPackageParam.packageName);
            Log.i(TAG, "Hook installed for " + loadPackageParam.packageName);
            Log.i(TAG, "Locale default now "
                    + Locale.getDefault().toLanguageTag()
                    + ", country="
                    + Locale.getDefault().getCountry());
        } catch (Throwable throwable) {
            XposedBridge.log("TelephonyCountryHook failed for "
                    + loadPackageParam.packageName
                    + ": "
                    + throwable);
            Log.e(TAG, "Hook failed for " + loadPackageParam.packageName, throwable);
        }
    }
}
