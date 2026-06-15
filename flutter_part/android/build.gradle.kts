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
   configurations.all {
       resolutionStrategy.eachDependency {
           if (requested.group == "com.google.firebase" &&
               requested.name == "firebase-dynamic-links" &&
               requested.version.isNullOrBlank()
           ) {
               useVersion("22.1.0")
               because("firebase_dynamic_links plugin requests dynamic-links without a version")
           }
       }
   }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
