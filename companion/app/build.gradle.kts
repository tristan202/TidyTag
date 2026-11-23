plugins {
    id("com.android.application")
    kotlin("android")
}

// release signing comes from tools/make-release.ps1 (-PtidytagKeystore=... from the user's own
// %USERPROFILE%\.tidytag\release.properties); the key never lives in the repository
val keystore = providers.gradleProperty("tidytagKeystore").orNull

android {
    namespace = "dk.tidytag.companion"
    compileSdk = 35
    defaultConfig {
        applicationId = "dk.tidytag.companion"
        minSdk = 30
        targetSdk = 35
        versionCode = 1
        versionName = providers.gradleProperty("appVersion").orNull ?: "1.0"
    }
    signingConfigs {
        if (keystore != null) create("release") {
            storeFile = file(keystore)
            storePassword = providers.gradleProperty("tidytagStorePassword").get()
            keyAlias = providers.gradleProperty("tidytagKeyAlias").get()
            keyPassword = providers.gradleProperty("tidytagKeyPassword").get()
        }
    }
    buildTypes {
        release {
            isMinifyEnabled = false
            if (keystore != null) signingConfig = signingConfigs.getByName("release")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    packaging { resources.excludes += "META-INF/*" }
}

dependencies {
    implementation(project(":core"))
}
