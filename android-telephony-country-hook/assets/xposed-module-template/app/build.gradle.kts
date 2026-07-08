plugins {
    id("com.android.application")
}

android {
    namespace = "com.flashy.test.telephonycountry"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.flashy.test.telephonycountry"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }
}

dependencies {
    compileOnly(files("libs/xposed-api-stubs.jar"))
}
