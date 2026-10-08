import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.ibem.mimic"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        create("release") {
            keyAlias = System.getenv("MIMIC_KEY_ALIAS")
                ?: (project.findProperty("MIMIC_KEY_ALIAS") as String?)
                ?: (keystoreProperties.getProperty("keyAlias") as String?)
            keyPassword = System.getenv("MIMIC_KEY_PASSWORD")
                ?: (project.findProperty("MIMIC_KEY_PASSWORD") as String?)
                ?: (keystoreProperties.getProperty("keyPassword") as String?)
            val storeFilePath = System.getenv("MIMIC_STORE_FILE")
                ?: (project.findProperty("MIMIC_STORE_FILE") as String?)
                ?: (keystoreProperties.getProperty("storeFile") as String?)
            if (storeFilePath != null) {
                storeFile = file(storeFilePath)
            }
            storePassword = System.getenv("MIMIC_STORE_PASSWORD")
                ?: (project.findProperty("MIMIC_STORE_PASSWORD") as String?)
                ?: (keystoreProperties.getProperty("storePassword") as String?)
        }
    }

    defaultConfig {
        applicationId = "com.ibem.mimic"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

dependencies {
    implementation("androidx.biometric:biometric:1.1.0")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
