// Kite's engine: search, routing, cameras, Waze... no screens. Shared by the Android and iPhone apps.
// jvm() is what the Android app uses; the iOS targets go into the iPhone app.
plugins {
    id("org.jetbrains.kotlin.multiplatform")
}

kotlin {
    jvm {
        compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) }
        testRuns["test"].executionTask.configure {
            useJUnit()
            // Live checks against the real servers only when asked: `-Plive`.
            systemProperty("kite.live", providers.gradleProperty("live").isPresent.toString())
            testLogging { events("failed"); exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL }
        }
    }
    iosArm64()
    iosSimulatorArm64()

    compilerOptions {
        optIn.addAll("kotlin.uuid.ExperimentalUuidApi", "kotlin.time.ExperimentalTime", "kotlin.io.encoding.ExperimentalEncodingApi", "kotlinx.cinterop.ExperimentalForeignApi")
        freeCompilerArgs.add("-Xexpect-actual-classes")
    }

    sourceSets {
        commonMain.dependencies {
            api("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.11.0")
            api("io.ktor:ktor-client-core:3.6.1")
            implementation("org.jetbrains.kotlinx:kotlinx-datetime:0.8.0")
        }
        jvmMain.dependencies {
            implementation("io.ktor:ktor-client-okhttp:3.6.1")
        }
        iosMain.dependencies {
            implementation("io.ktor:ktor-client-darwin:3.6.1")
        }
        commonTest.dependencies {
            implementation(kotlin("test"))
        }
    }
}
