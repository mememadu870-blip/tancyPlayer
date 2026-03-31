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
subprojects {
    fun ensureNamespace() {
        val androidExt = extensions.findByName("android") ?: return
        val getNamespace = androidExt.javaClass.methods.find { it.name == "getNamespace" }
        val setNamespace = androidExt.javaClass.methods.find { it.name == "setNamespace" }
        if (getNamespace != null && setNamespace != null) {
            val current = getNamespace.invoke(androidExt) as? String
            if (current.isNullOrBlank()) {
                val fallback = "dev.tancy.${project.name.replace("-", "_")}"
                setNamespace.invoke(androidExt, fallback)
            }
        }
    }

    plugins.withId("com.android.library") { ensureNamespace() }
    plugins.withId("com.android.application") { ensureNamespace() }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
