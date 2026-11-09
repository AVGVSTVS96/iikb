pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode = RepositoriesMode.FAIL_ON_PROJECT_REPOS
    repositories {
        google()
        mavenCentral()
        // sherpa-onnx, which runs Parakeet, publishes its Android library only as a release asset on GitHub.
        ivy {
            url = uri("https://github.com/k2-fsa/sherpa-onnx/releases/download")
            patternLayout { artifact("v[revision]/[module]-[revision].[ext]") }
            metadataSources { artifact() }
            content { includeGroup("com.k2fsa.sherpa.onnx") }
        }
    }
}

rootProject.name = "iikb"
include(":app")
