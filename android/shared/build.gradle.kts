// The whole Kite app, shared by Android and iPhone: every screen, the map, navigation.
// Only what each phone does its own way (GPS, voice, the lock-screen turn...) is in androidMain/iosMain.
import org.jetbrains.kotlin.gradle.plugin.mpp.apple.XCFramework

val withAndroid = !providers.gradleProperty("noAndroid").isPresent

plugins {
    id("org.jetbrains.kotlin.multiplatform")
    id("org.jetbrains.compose")
    id("org.jetbrains.kotlin.plugin.compose")
}
// Android: the KMP Android target lives in its own file so this one never names an Android class.
if (withAndroid) apply(from = "android-target.gradle.kts")

kotlin {
    val xcf = XCFramework("KiteShared")
    listOf(iosArm64(), iosSimulatorArm64()).forEach {
        it.binaries.framework {
            baseName = "KiteShared"
            isStatic = false
            export(project(":core"))
            xcf.add(this)
        }
    }

    compilerOptions {
        optIn.addAll(
            "kotlin.uuid.ExperimentalUuidApi", "kotlin.time.ExperimentalTime",
            "kotlinx.cinterop.ExperimentalForeignApi", "kotlinx.cinterop.BetaInteropApi",
            "androidx.compose.material3.ExperimentalMaterial3Api", "androidx.compose.foundation.ExperimentalFoundationApi",
            "androidx.compose.foundation.layout.ExperimentalLayoutApi",
        )
        freeCompilerArgs.add("-Xexpect-actual-classes")
    }

    sourceSets {
        commonMain.dependencies {
            api(project(":core"))
            implementation("org.jetbrains.compose.runtime:runtime:1.12.2")
            implementation("org.jetbrains.compose.foundation:foundation:1.12.2")
            implementation("org.jetbrains.compose.ui:ui:1.12.2")
            implementation("org.jetbrains.compose.animation:animation:1.12.2")
            implementation("org.jetbrains.compose.material3:material3:1.9.0")
            implementation("org.jetbrains.compose.material:material-icons-extended:1.7.3")
            implementation("org.jetbrains.compose.components:components-resources:1.12.2")
            implementation("org.jetbrains.compose.ui:ui-backhandler:1.12.2")
            implementation("org.jetbrains.androidx.lifecycle:lifecycle-runtime-compose:2.11.0")
            implementation("org.maplibre.compose:maplibre-compose:0.20.0")
            implementation("io.coil-kt.coil3:coil-compose:3.6.3")
            implementation("io.coil-kt.coil3:coil-network-ktor3:3.6.3")
            implementation("org.jetbrains.kotlinx:kotlinx-datetime:0.8.0")
        }
    }
}

compose.resources {
    publicResClass = false
    packageOfResClass = "app.kite.resources"
    generateResClass = always
}
