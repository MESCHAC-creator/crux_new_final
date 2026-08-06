import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use {
        keystoreProperties.load(it)
    }
}

android {
    namespace = "com.schac_crux.app"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    buildFeatures {
        compose = true
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias") ?: ""
            keyPassword = keystoreProperties.getProperty("keyPassword") ?: ""
            storeFile = keystoreProperties.getProperty("storeFile")?.let {
                rootProject.file(it)
            }
            storePassword = keystoreProperties.getProperty("storePassword") ?: ""
        }
    }

    defaultConfig {
        applicationId = "com.schac_crux.app"
        minSdk = 24
        targetSdk = 35
        versionCode = 4
        versionName = "2.38.1"
        multiDexEnabled = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin", "src/main/java")
            manifest.srcFile("src/main/AndroidManifest.xml")
        }
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = true
            isShrinkResources = true
            signingConfig = signingConfigs.getByName("release")

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }

        getByName("debug") {
            isDebuggable = true
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    lint {
        disable.addAll(
            listOf(
                "MissingDimensionRegistration",
                "GradleDependency",
                "MissingTranslation",
                "ExtraTranslation"
            )
        )
    }
}

flutter {
    source = "../.."
}

dependencies {

    // Java 17 desugaring
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // Firebase
    implementation(platform("com.google.firebase:firebase-bom:33.12.0"))
    implementation("com.google.firebase:firebase-analytics")

    // AndroidX
    implementation("androidx.core:core:1.15.0")
    implementation("androidx.multidex:multidex:2.0.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")

    // Compose — pour le fond vidéo virtuel (segmentation MLKit) et futures vues natives
    implementation(platform("androidx.compose:compose-bom:2024.10.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")

    // Persistance des préférences de fond d'écran
    implementation("androidx.datastore:datastore-preferences:1.1.1")

    // Chargement d'images
    implementation("io.coil-kt:coil-compose:2.7.0")

    // Segmentation du fond vidéo
    implementation("com.google.mlkit:segmentation-selfie:16.0.0-beta6")

    // LiveKit natif : normalement déjà tiré transitivement par le plugin Flutter
    // `livekit_client`. Ligne explicite conservée à la demande, mais à surveiller —
    // en cas d'erreur "duplicate class" au build, retirer cette ligne et laisser
    // le plugin Flutter fournir la version native.
    implementation("io.livekit:livekit-android:2.11.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
}
