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

    packaging { jniLibs { useLegacyPackaging = false } }
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
}
