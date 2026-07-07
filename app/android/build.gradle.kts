allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    // Some plugins pin an old compileSdk in their own build.gradle (e.g.
    // image_cropper 9.0.0 → 33), which then fails AAR-metadata checks because
    // their AndroidX deps require 34+/36. Force every Android plugin module up
    // to 36 — backward-compatible; only the compile target changes, not
    // minSdk/targetSdk. Registered here (before evaluationDependsOn below forces
    // evaluation) so afterEvaluate is always valid.
    afterEvaluate {
        (extensions.findByName("android") as? com.android.build.gradle.BaseExtension)
            ?.compileSdkVersion(36)
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
