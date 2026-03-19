plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("org.jetbrains.kotlin.plugin.compose")  // ← add this
}

android {
    namespace = "com.example.aikomate_flutter"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    defaultConfig {
        applicationId = "com.example.aikomate_flutter"
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildFeatures {
        compose = true
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    dependencies {
        implementation("io.github.sceneview:arsceneview:2.3.3")
        implementation("androidx.activity:activity-compose:1.10.1")
        implementation("androidx.compose.ui:ui:1.10.0")
        implementation("androidx.compose.material3:material3:1.4.0")
        implementation("androidx.appcompat:appcompat:1.7.1")
    }
}

flutter {
    source = "../.."
}
