// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "QuickNotes",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "QuickNotes", targets: ["QuickNotes"])
    ],
    targets: [
        .target(
            name: "QuickNotesCore",
            path: "Sources/QuickNotesCore"
        ),
        .executableTarget(
            name: "QuickNotes",
            dependencies: ["QuickNotesCore"],
            path: "Sources/QuickNotes"
        ),
        .testTarget(
            name: "QuickNotesCoreTests",
            dependencies: ["QuickNotesCore"],
            path: "Tests/QuickNotesCoreTests"
        )
    ]
)
