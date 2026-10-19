// Algunos plugins (p. ej. connectivity_plus 4.x) compilan contra android-33 y
// sus dependencias (androidx.fragment 1.7.1, window, activity, ...) exigen
// compileSdk >= 34. Se fuerza 36 en todos los módulos *después* de su propia
// configuración para que el build de Android (teléfono/emulador) no falle en
// checkDebugAarMetadata. Debe registrarse antes de que se evalúen los
// subproyectos (evaluationDependsOn(":app") más abajo), o afterEvaluate
// lanzaría "project is already evaluated".
subprojects {
    if (!project.state.executed) {
        project.afterEvaluate {
            extensions.findByName("android")?.let { ext ->
                (ext as? com.android.build.gradle.BaseExtension)?.compileSdkVersion(36)
            }
        }
    }
}

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
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
