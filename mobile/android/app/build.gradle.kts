import java.io.FileInputStream
import java.net.URI
import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. android/key.properties is gitignored and never committed; it holds
//   storePassword=...  keyPassword=...  keyAlias=...  storeFile=/path/to/yoma-release.jks
// storeFile defaults to ~/yoma-release.jks. Without the file, release builds are signed
// with the debug key, as before, and Gradle says so. See docs/deploy-environments.md.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) FileInputStream(file).use { load(it) }
}
val hasReleaseKey = keyProperties.getProperty("storePassword") != null

android {
    namespace = "gh.yomatriage.yoma_triage"
    compileSdk = flutter.compileSdkVersion
    // Use installed Build-Tools 36; AGP 8.11 defaults to 35.0.0 which failed to
    // download cleanly on this host (corrupt zip from Google CDN).
    buildToolsVersion = "36.0.0"
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "gh.yomatriage.yoma_triage"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(
                    keyProperties.getProperty("storeFile")
                        ?: "${System.getProperty("user.home")}/yoma-release.jks",
                )
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "android/key.properties not found: signing the release with the DEBUG key. " +
                        "Don't distribute this build.",
                )
                signingConfigs.getByName("debug")
            }
        }
    }

    lint {
        checkReleaseBuilds = false
        abortOnError = false
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

// A3: a release build fails closed. It must carry production settings and an HTTPS server
// address, or say plainly that it is a test build (YOMA_TEST_RELEASE=true), which the app
// then labels on every screen. lib/release_settings.dart checks the same rules at startup.
// The release build command is in docs/deploy-environments.md.
fun dartDefines(): Map<String, String> {
    val raw = project.findProperty("dart-defines")?.toString() ?: return emptyMap()
    return raw.split(",")
        .filter { it.isNotBlank() }
        .mapNotNull { entry ->
            val decoded = String(Base64.getDecoder().decode(entry), Charsets.UTF_8)
            val split = decoded.indexOf('=')
            if (split < 0) null else decoded.substring(0, split) to decoded.substring(split + 1)
        }
        .toMap()
}

val localHosts = setOf("localhost", "127.0.0.1", "10.0.2.2", "0.0.0.0")

fun releaseSettingsProblems(defines: Map<String, String>): List<String> {
    val appEnv = defines["APP_ENV"].orEmpty().trim()
    if (defines["YOMA_TEST_RELEASE"] == "true") {
        return if (appEnv == "production") {
            listOf("YOMA_TEST_RELEASE=true can't be combined with APP_ENV=production")
        } else {
            emptyList()
        }
    }
    val problems = mutableListOf<String>()
    if (appEnv != "production") problems += "APP_ENV must be production (got '$appEnv')"
    val url = defines["API_BASE_URL"].orEmpty().trim()
    val host = runCatching { URI(url).host }.getOrNull().orEmpty().lowercase()
    if (!url.startsWith("https://") || host.isEmpty()) {
        problems += "API_BASE_URL must be an https:// address (got '$url')"
    } else if (host in localHosts) {
        problems += "API_BASE_URL must not point at this computer or the emulator (got '$url')"
    }
    if (defines["API_KEY"].orEmpty().isBlank()) problems += "API_KEY must be set"
    return problems
}

val checkReleaseSettings = tasks.register("checkReleaseSettings") {
    val problems = releaseSettingsProblems(dartDefines())
    doLast {
        if (problems.isNotEmpty()) {
            throw GradleException(
                "Refusing to build a release without production settings:\n" +
                    problems.joinToString("\n") { "  - $it" } +
                    "\nSee docs/deploy-environments.md for the release build command.",
            )
        }
    }
}

tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    dependsOn(checkReleaseSettings)
}
