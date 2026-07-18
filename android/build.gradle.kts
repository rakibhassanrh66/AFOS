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
    // Several transitive androidx deps now require a newer compileSdk than this
    // Flutter channel's default (33): fragment/window (via flutter_displaymode)
    // need 34, camera 1.5.0 needs 35, browser 1.9.0 needs 36. Plugin modules
    // otherwise compile against flutter.compileSdkVersion and fail their own
    // checkDebugAarMetadata even after :app is bumped. Force every Android plugin
    // module to 36 so they all agree. withGroovyBuilder avoids needing AGP types
    // on the root buildscript classpath. compileSdk only affects which APIs
    // compile — targetSdk/minSdk are untouched.
    //
    // Skip already-evaluated projects: evaluationDependsOn(":app") above eagerly
    // evaluates :app, and afterEvaluate can't be registered on an evaluated
    // project. :app already pins 36 in its own build.gradle.kts, so that's fine.
    if (!project.state.executed) {
        afterEvaluate {
            extensions.findByName("android")?.withGroovyBuilder {
                "compileSdkVersion"(36)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
