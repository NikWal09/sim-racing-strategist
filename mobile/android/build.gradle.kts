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

    // Wymuszamy compileSdk 36 na wszystkich pluginach (np. file_picker domyślnie
    // kompiluje się na 34, a flutter_plugin_android_lifecycle wymaga 36).
    // afterEvaluate -> nadpisuje wartość ustawioną przez plugin w jego android{}.
    // Rejestrujemy to PRZED evaluationDependsOn(":app"), żeby uniknąć błędu
    // "Cannot run afterEvaluate when project already evaluated".
    afterEvaluate {
        extensions.findByName("android")?.let { ext ->
            (ext as com.android.build.gradle.BaseExtension).compileSdkVersion(36)
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
