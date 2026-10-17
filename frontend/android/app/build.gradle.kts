plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

extensions.configure<com.android.build.api.dsl.ApplicationExtension> {
    namespace = "com.pmay.frontend"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
        isCoreLibraryDesugaringEnabled = true // needed by flutter_local_notifications
    }

    defaultConfig {
        applicationId = "com.pmay.frontend"
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    add("coreLibraryDesugaring", "com.android.tools:desugar_jdk_libs:2.1.4")
}

// Firebase push: only active when google-services.json is present (app still builds without it)
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}