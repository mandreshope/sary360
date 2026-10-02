import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Emplacement de l'OpenCV Android SDK (module natif d'assemblage) :
// clé opencv.dir de local.properties, sinon variable OPENCV_ANDROID_SDK,
// sinon third_party/OpenCV-android-sdk à la racine du projet.
val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val opencvSdkDir: String = localProperties.getProperty("opencv.dir")
    ?: System.getenv("OPENCV_ANDROID_SDK")
    ?: rootProject.file("../third_party/OpenCV-android-sdk").absolutePath

android {
    namespace = "com.mandreshope.sary360"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.mandreshope.sary360"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }

        externalNativeBuild {
            cmake {
                arguments += listOf(
                    "-DOpenCV_DIR=$opencvSdkDir/sdk/native/jni",
                    // Les bibliothèques statiques du SDK sont compilées
                    // avec la libc++ partagée.
                    "-DANDROID_STL=c++_shared",
                )
            }
        }
    }

    // Module C++ d'assemblage (OpenCV, appelé depuis Dart via FFI).
    externalNativeBuild {
        cmake {
            path = file("../../native/stitcher/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    // Extrait les .so sur le disque à l'installation : OpenCV liste le dossier
    // de ses bibliothèques pour chercher des plugins de parallélisme, ce qui
    // échoue (E/cv::error) quand elles restent compressées dans l'APK.
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
