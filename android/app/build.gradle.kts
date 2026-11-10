import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

val repo = rootProject.projectDir.parentFile
val commits = providers.exec { commandLine("git", "-C", repo.path, "rev-list", "--count", "HEAD") }
    .standardOutput.asText.map { it.trim().toInt() }

// The release key lives outside git (scripts/android makes it once), so every build installs over the last one.
val signing = file(System.getenv("IIKB_ANDROID_KEYS") ?: "${System.getProperty("user.home")}/.local/share/iikb/android/release.properties")
    .takeIf { it.exists() }
    ?.let { file -> Properties().apply { file.inputStream().use(::load) }.also { it["dir"] = file.parent } }

android {
    namespace = "com.shahidy.iikb"
    compileSdk = 37
    ndkVersion = "30.0.16248370"

    defaultConfig {
        applicationId = "com.shahidy.iikb"
        minSdk = 28
        targetSdk = 37
        versionCode = commits.get()
        versionName = "0.1.${commits.get()}"
        ndk { abiFilters += "arm64-v8a" }
    }

    signingConfigs {
        if (signing != null) {
            create("release") {
                storeFile = file("${signing["dir"]}/${signing["storeFile"]}")
                storePassword = signing["storePassword"] as String
                keyAlias = signing["keyAlias"] as String
                keyPassword = signing["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.findByName("release")
        }
    }

    buildFeatures { compose = true }

    androidResources { noCompress += listOf("lexicon", "network", "swipe") }

    packaging { jniLibs { useLegacyPackaging = true } }
}

// KeyboardCore and its Android bridge, built for arm64 with the Swift SDK for Android, beside the NDK's C++ runtime.
abstract class SwiftLibrary : DefaultTask() {
    @get:InputFiles abstract val sources: ConfigurableFileCollection
    @get:Internal abstract val pkg: DirectoryProperty
    @get:Input abstract val ndk: Property<String>
    @get:OutputDirectory abstract val output: DirectoryProperty
    @get:Inject abstract val exec: ExecOperations

    @TaskAction
    fun build() {
        val pkg = pkg.get().asFile
        exec.exec {
            workingDir = pkg
            commandLine(
                "swift", "build", "-c", "release", "--swift-sdk", "aarch64-unknown-linux-android28",
                "--static-swift-stdlib", "--product", "iikb",
            )
        }
        val abi = output.get().asFile.resolve("arm64-v8a").apply { deleteRecursively(); mkdirs() }
        pkg.resolve(".build/out/Products/Release-android-aarch64/libiikb.so").copyTo(abi.resolve("libiikb.so"))
        File(ndk.get(), "toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so")
            .copyTo(abi.resolve("libc++_shared.so"))
    }
}

/** The API keys kept out of git (`Resources/Keys`), as assets; a build without KLIPY's has no GIFs. */
abstract class Keys : DefaultTask() {
    @get:InputFiles abstract val keys: ConfigurableFileCollection
    @get:OutputDirectory abstract val output: DirectoryProperty

    @TaskAction
    fun copy() {
        val out = output.get().asFile.apply { deleteRecursively(); mkdirs() }
        keys.files.filter { it.isFile }.forEach { it.copyTo(out.resolve(it.name)) }
    }
}

val keys = tasks.register<Keys>("keys") {
    keys.from(fileTree(repo.resolve("Packages/KeyboardModules/Sources/FullKeyboard/Resources/Keys")) { include("*.key") })
    output = layout.buildDirectory.dir("generated/keys")
}

/**
 * Settings › Changelog's `changelog.json`: each change with its build and day, newest first, from the `Changelog:`
 * trailers of commits to android/, as scripts/phone writes iOS's `IIKBChangelog`. The Core it shares with iOS came
 * whole in its first build, so iOS's older lines aren't Android's changes. `android/changelog.tsv` rewords a commit's
 * line (its hash, a tab, the line) where the trailer spoke of iOS, which someone on Android has never seen. A trailer
 * starts "On Android, " for the site, which lists every commit's; here, where everyone is on Android, that goes.
 */
abstract class Changelog : DefaultTask() {
    @get:Input abstract val head: Property<String>
    @get:Internal abstract val repo: DirectoryProperty
    @get:InputFile abstract val reworded: RegularFileProperty
    @get:OutputDirectory abstract val output: DirectoryProperty

    private fun git(vararg args: String): String {
        val process = ProcessBuilder("git", "-C", repo.get().asFile.path, *args).redirectErrorStream(true).start()
        return process.inputStream.bufferedReader().readText().also { process.waitFor() }
    }

    @TaskAction
    fun write() {
        val rewording = reworded.get().asFile.readLines().filter { it.isNotBlank() }
            .associate { line -> line.substringBefore('\t') to line.substringAfter('\t') }
        val entries = git("log", "--format=%H%x1f%cs%x1f%(trailers:key=Changelog,valueonly,separator=%x1e)", "--", "android")
            .lines()
            .filter { it.isNotBlank() }
            .flatMap { line ->
                val (sha, day, trailers) = line.split("\u001f")
                val changes = rewording.entries.firstOrNull { sha.startsWith(it.key) }?.let { listOf(it.value) }
                    ?: trailers.split("\u001e").filter { it.isNotBlank() }
                        .map { it.trim().removePrefix("On Android, ").replaceFirstChar(Char::uppercase) }
                changes.map { Triple(sha, day, it) }
            }
        val rows = entries.map { (sha, day, change) ->
            mapOf("build" to git("rev-list", "--count", sha).trim().toInt(), "date" to day, "change" to change)
        }.sortedByDescending { it["build"] as Int }.take(60)
        val out = output.get().asFile.apply { deleteRecursively(); mkdirs() }
        out.resolve("changelog.json").writeText(groovy.json.JsonOutput.toJson(rows))
    }
}

val commit = providers.exec { commandLine("git", "-C", repo.path, "rev-parse", "HEAD") }.standardOutput.asText.map { it.trim() }
val checkout = layout.dir(provider { repo })
val changelog = tasks.register<Changelog>("changelog") {
    head = commit
    this.repo = checkout
    reworded.set(rootProject.file("changelog.tsv"))
    output = layout.buildDirectory.dir("generated/changelog")
}

val swift = tasks.register<SwiftLibrary>("swiftLibrary") {
    pkg = rootProject.layout.projectDirectory
    sources.from(
        rootProject.file("Package.swift"), rootProject.file("Sources"),
        repo.resolve("Packages/KeyboardModules/Sources/KeyboardCore"),
    )
    ndk = androidComponents.sdkComponents.ndkDirectory.map { it.asFile.path }
    output = layout.buildDirectory.dir("generated/swift")
}

androidComponents {
    onVariants { variant ->
        variant.sources.jniLibs?.addGeneratedSourceDirectory(swift, SwiftLibrary::output)
        variant.sources.assets?.addGeneratedSourceDirectory(keys, Keys::output)
        variant.sources.assets?.addGeneratedSourceDirectory(changelog, Changelog::output)
        variant.sources.assets?.addStaticSourceDirectory(
            repo.resolve("Packages/KeyboardModules/Sources/KeyboardEnglish/Resources").path,
        )
    }
}

dependencies {
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.material3)
    implementation(libs.compose.ui)
    implementation(libs.compose.tooling)
    implementation(libs.activity.compose)
    implementation(libs.core)
    implementation(libs.serialization.json)
    implementation(libs.backdrop)
    implementation(libs.coil.compose)
    implementation(libs.coil.gif)
    implementation(libs.coil.network)
    implementation(variantOf(libs.sherpa.onnx) { artifactType("aar") })
}
