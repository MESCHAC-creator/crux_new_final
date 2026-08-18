plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.schac_crux.app"
    compileSdk = 35
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.schac_crux.app"
        minSdk = 23
        targetSdk = 35
        versionCode = 4
        versionName = "2.38.1"
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
            isDebuggable = true
            isMinifyEnabled = true
        }
    }

    lintOptions {
        disable("MissingFirebaseInstanceId")
        disable("FirebaseInstanceIdUsage")
    }

    packagingOptions {
        exclude("META-INF/proguard/androidx-*.pro")
        exclude("META-INF/kotlin/**")
        exclude("META-INF/services/javax.annotation.processing.Processor")
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    implementation("androidx.work:work-runtime-ktx:2.8.1")
    
    // Firebase BOM
    val firebaseBom = platform("com.google.firebase:firebase-bom:32.7.0")
    implementation(firebaseBom)
    
    implementation("com.google.firebase:firebase-auth-ktx")
    implementation("com.google.firebase:firebase-firestore-ktx")
    implementation("com.google.firebase:firebase-messaging-ktx")
    implementation("com.google.firebase:firebase-analytics-ktx")
    implementation("com.google.firebase:firebase-storage-ktx")
    
    // Kotlin
    implementation("org.jetbrains.kotlin:kotlin-stdlib:1.9.24")
    
    // Jetpack Compose (si utilisé)
    implementation("androidx.compose.ui:ui:1.6.0")
    implementation("androidx.compose.material3:material3:1.1.0")
}
