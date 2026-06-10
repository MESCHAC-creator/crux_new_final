plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

apply(plugin = "com.google.gms.google-services")

android {
    namespace = "com.example.crux"
    compileSdk = 35
    ndkVersion = "27.0.12077973"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    signingConfigs {
        create("release") {
            storeFile = file("crux.keystore")
            storePassword = "crux2024!"
            keyAlias = "crux_key"
            keyPassword = "crux2024!"
        }
    }

    defaultConfig {
        applicationId = "com.example.crux"
        minSdk = 24
        targetSdk = 35
        versionCode = 3
        versionName = "2.3.0"
        multiDexEnabled = true
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
        debug {
            signingConfig = signingConfigs.getByName("release")
            isDebuggable = true
        }
    }

    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }

    packaging {
        resources {
            excludes += setOf(
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE",
                "META-INF/LICENSE.txt",
                "META-INF/NOTICE",
                "META-INF/NOTICE.txt"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.multidex:multidex:2.0.1")
}

// Ensure the APK lands where flutter_tools/gradle.dart expects it.
// The Flutter Gradle plugin attaches a doLast to packageRelease but the copy
// may silently fail with certain AGP/Gradle combinations; this guarantees it.
afterEvaluate {
    tasks.matching { it.name == "packageRelease" }.configureEach {
        doLast {
            val apkSrc = layout.buildDirectory.file("outputs/apk/release/app-release.apk").get().asFile
            val flutterApkDir = File(rootProject.projectDir, "../build/app/outputs/flutter-apk")
            if (apkSrc.exists()) {
                flutterApkDir.mkdirs()
                apkSrc.copyTo(File(flutterApkDir, "app-release.apk"), overwrite = true)
                println("flutter-apk: copied ${apkSrc.absolutePath}")
            }
        }
    }
}
