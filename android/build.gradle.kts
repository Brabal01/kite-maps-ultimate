// The Android Gradle plugin is only loaded when building for Android, so the shared app and the
// engine can be built and checked on a machine with no Android SDK (`-PnoAndroid` or `-PcoreOnly`).
buildscript {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
    dependencies {
        if (!project.hasProperty("noAndroid") && !project.hasProperty("coreOnly")) {
            classpath("com.android.tools.build:gradle:9.4.1")
        }
    }
}

// Loaded once here, so every module shares the same Kotlin and Compose plugins.
plugins {
    id("org.jetbrains.kotlin.multiplatform") apply false
    id("org.jetbrains.kotlin.plugin.compose") apply false
    id("org.jetbrains.compose") apply false
}
