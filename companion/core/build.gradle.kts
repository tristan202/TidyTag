plugins {
    kotlin("jvm")
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    implementation("org.nanohttpd:nanohttpd:2.3.1")
    testImplementation("org.junit.jupiter:junit-jupiter:5.11.3")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

tasks.test {
    useJUnitPlatform()
}

// one runnable jar for TidyTag's tests: java -jar core.jar --root <dir> --port <n> --token <t>
tasks.jar {
    manifest { attributes["Main-Class"] = "dk.tidytag.companion.core.MainKt" }
    from(configurations.runtimeClasspath.get().map { if (it.isDirectory) it else zipTree(it) })
    duplicatesStrategy = DuplicatesStrategy.EXCLUDE
}
