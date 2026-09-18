import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingProperties = Properties()
val signingPropertiesFile = rootProject.file("key.properties")
if (signingPropertiesFile.exists()) {
    signingPropertiesFile.inputStream().use(signingProperties::load)
}

fun signingValue(name: String): String? =
    System.getenv(name) ?: signingProperties.getProperty(name.lowercase().replace('_', '.'))

val releaseStoreFile = signingValue("ANDROID_KEYSTORE_FILE")
    ?: signingProperties.getProperty("storeFile")
val releaseStorePassword = signingValue("ANDROID_KEYSTORE_PASSWORD")
    ?: signingProperties.getProperty("storePassword")
val releaseKeyAlias = signingValue("ANDROID_KEY_ALIAS")
    ?: signingProperties.getProperty("keyAlias")
val releaseKeyPassword = signingValue("ANDROID_KEY_PASSWORD")
    ?: signingProperties.getProperty("keyPassword")

android {
    namespace = "com.alkawn.alkawn_alshamil"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.alkawn.alkawn_alshamil"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.create("production") {
                val storeFilePath = releaseStoreFile
                    ?: error("Production signing is not configured: ANDROID_KEYSTORE_FILE")
                storeFile = file(storeFilePath)
                storePassword = releaseStorePassword
                    ?: error("Production signing is not configured: ANDROID_KEYSTORE_PASSWORD")
                keyAlias = releaseKeyAlias
                    ?: error("Production signing is not configured: ANDROID_KEY_ALIAS")
                keyPassword = releaseKeyPassword
                    ?: error("Production signing is not configured: ANDROID_KEY_PASSWORD")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
