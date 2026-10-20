// swift-tools-version:5.9
// MixMeister 8 — app de macOS (AppKit) sobre el motor C++ de engine/.
//
// Compilar y abrir (en el Mac, Terminal):
//   swift build -c release && app/bundle.sh
import PackageDescription

let package = Package(
    name: "MixMeister8",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MixMeister8", targets: ["MixMeister8"])],
    targets: [
        .target(
            name: "MMNEngine",
            path: "engine",
            exclude: ["apps", "tests", "tools", "docs", "validacion", "CMakeLists.txt", "README.md", "third_party"],
            sources: ["src", "capi/mmn_c.cpp"],
            publicHeadersPath: "capi/include",
            cxxSettings: [.headerSearchPath("include"), .headerSearchPath("third_party/minimp3")],
            linkerSettings: [.linkedFramework("AudioToolbox"), .linkedFramework("CoreFoundation")]),
        .executableTarget(
            name: "MixMeister8",
            dependencies: ["MMNEngine"],
            path: "app/Sources/MixMeister8",
            linkerSettings: [.linkedLibrary("sqlite3")]),
    ],
    cxxLanguageStandard: .cxx20)
