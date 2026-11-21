// Applied by build.gradle.kts only when building for Android.
apply(plugin = "com.android.kotlin.multiplatform.library")

extensions.configure<org.jetbrains.kotlin.gradle.dsl.KotlinMultiplatformExtension> {
    (this as ExtensionAware).extensions.configure<com.android.build.api.dsl.KotlinMultiplatformAndroidLibraryTarget>("android") {
        namespace = "app.kite.shared"
        compileSdk = 37
        minSdk = 26
        androidResources { enable = true }
        compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) }
    }
    sourceSets.getByName("androidMain").dependencies {
        implementation("androidx.core:core-ktx:1.17.0")
        implementation("androidx.activity:activity-compose:1.12.0")
        implementation("androidx.webkit:webkit:1.17.0")
        implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
    }
}
