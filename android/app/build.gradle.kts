import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}


val localProperties = Properties()

val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localProperties.load(FileInputStream(localPropertiesFile))
    println("Successfully loaded local.properties")
} else {
    println("WARNING: local.properties not found. API key placeholder will not be replaced.")
}
// ------------------- Start of Kotlin Keystore Logic -------------------
val keystorePropertiesFile = rootProject.file("key.properties")
println("Looking for key.properties at: ${keystorePropertiesFile.absolutePath}")
println("File exists: ${keystorePropertiesFile.exists()}")

val keystoreProperties = Properties()
val keystorePropertiesExist = keystorePropertiesFile.exists()
if (keystorePropertiesExist) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
    println("Successfully loaded key.properties")
} else {
    println("WARNING: key.properties not found at ${keystorePropertiesFile.absolutePath}")
}
// ------------------- End of Kotlin Keystore Logic -------------------

android {
    namespace = "com.example.the_money_gigs"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.themoneygigs.moneygigs"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode.toInt()
        versionName = flutter.versionName
        manifestPlaceholders["googleApiKey"] = localProperties.getProperty("googleApiKey")

    }
    
    signingConfigs {
    create("release") {
        if (keystorePropertiesExist) {
            keyAlias = keystoreProperties.getProperty("keyAlias") ?: throw GradleException("keyAlias not found in key.properties")
            keyPassword = keystoreProperties.getProperty("keyPassword") ?: throw GradleException("keyPassword not found in key.properties")
            storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) } ?: throw GradleException("storeFile not found in key.properties")
            storePassword = keystoreProperties.getProperty("storePassword") ?: throw GradleException("storePassword not found in key.properties")
        } else {
            // Use debug signing for release builds (not recommended for production)
            initWith(signingConfigs.getByName("debug"))
        }
    }
}
    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
        }
        getByName("debug") {
            // Debug config
        }
    }
}

kotlin {
    jvmToolchain(17)
}

flutter {
    source = "../.."
}

