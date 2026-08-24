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

// ---------------------------------------------------------------------------
// file_picker 12.0.0 与 AGP 9 的兼容修补
//
// 该插件的 android/build.gradle 在检测到 AGP 9+ 时会**跳过**
// `org.jetbrains.kotlin.android` 插件与 kotlinOptions，前提是工程启用了 AGP 内建
// Kotlin（android.builtInKotlin=true）。但本工程的其他 Flutter 插件仍在显式
// 应用 kotlin-android，一旦开启内建 Kotlin 就会直接构建失败，因此
// gradle.properties 中保持 `android.builtInKotlin=false`。
//
// 两者叠加的结果是 file_picker 的 Kotlin 源码根本不参与编译，Java 侧的
// GeneratedPluginRegistrant 会报 “找不到符号 类 FilePickerPlugin”。
// 这里针对该子工程补回 Kotlin 插件与 JVM 17 目标（与其 compileOptions 一致）。
//
// 待 file_picker 适配「非内建 Kotlin 的 AGP 9」或本工程整体迁移到内建 Kotlin
// 后，可删除本段。
subprojects {
    if (name == "file_picker") {
        plugins.withId("com.android.library") {
            if (!plugins.hasPlugin("org.jetbrains.kotlin.android")) {
                apply(plugin = "org.jetbrains.kotlin.android")
            }
        }
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions.jvmTarget.set(
                org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17,
            )
        }
    }
}
