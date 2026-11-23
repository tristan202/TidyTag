plugins {
    kotlin("jvm")
    `java-library`
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    api("org.nanohttpd:nanohttpd:2.3.1") // CompanionServer extends NanoHTTPD
    testImplementation("org.junit.jupiter:junit-jupiter:5.11.3")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

tasks.test {
    useJUnitPlatform()
}

// one runnable jar for TidyTag's tests: java -jar companion-desktop.jar --root <dir> --port <n> --token <t>
tasks.register<Jar>("desktopJar") {
    archiveFileName.set("companion-desktop.jar")
    manifest { attributes["Main-Class"] = "dk.tidytag.companion.core.MainKt" }
    from(sourceSets.main.get().output)
    from(configurations.runtimeClasspath.get().map { if (it.isDirectory) it else zipTree(it) })
    duplicatesStrategy = DuplicatesStrategy.EXCLUDE
}
