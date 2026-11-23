plugins {
    id("com.android.application")
    kotlin("android")
}

android {
    namespace = "dk.tidytag.companion"
    compileSdk = 35
    defaultConfig {
        applicationId = "dk.tidytag.companion"
        minSdk = 30
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
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
