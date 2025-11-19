import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("kotlin-kapt")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val media3Version = (project.findProperty("MEDIA3_VERSION") as String?) ?: "1.4.1"

android {
    namespace = "com.example.coalition_app_v2"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications and other libs using java.time, etc.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        // Align with compileOptions; AGP 8.x and Flutter stable use JDK 17
        jvmTarget = "17"
    }

    // Suppress obsolete -source/-target warnings by passing lint options to the Java compiler
    tasks.withType<JavaCompile> {
        options.compilerArgs.addAll(listOf("-Xlint:-options"))
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.coalition_app_v2"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.github.bumptech.glide:glide:4.16.0")
    kapt("com.github.bumptech.glide:compiler:4.16.0")
    implementation("com.otaliastudios:transcoder:0.10.5") {
        exclude(group = "com.google.android.exoplayer")
    }
    implementation("androidx.work:work-runtime-ktx:2.9.0")
    // Use a jar-publishing version of the Java TUS client (0.5.x line)
    // Pin to a published version; 0.5.1 is the latest available in Maven Central
    implementation("io.tus.java.client:tus-java-client:0.5.1")
    implementation("io.tus.android.client:tus-android-client:0.1.12")
    // Required for CoroutineWorker + suspend setProgress()
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    // Core library desugaring support libs (stable 2.x line)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    implementation("androidx.media3:media3-exoplayer:$media3Version")
    implementation("androidx.media3:media3-transformer:$media3Version")
    implementation("androidx.media3:media3-common:$media3Version")
    implementation("androidx.media3:media3-ui:$media3Version")
    implementation("androidx.media3:media3-effect:$media3Version")
}

// Ensure EVERY compile task uses JVM 17 (Kotlin, KAPT, and Java)
tasks.withType<KotlinCompile>().configureEach {
    kotlinOptions {
        jvmTarget = "17"
    }
}
