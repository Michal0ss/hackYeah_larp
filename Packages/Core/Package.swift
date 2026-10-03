// swift-tools-version: 5.9
import PackageDescription

// One library per module. Each module has one owner (see WORKINGPLAN.md).
// New code goes here, not into the Xcode project file.
let package = Package(
    name: "Core",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Contracts", targets: ["Contracts"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "Analysis", targets: ["Analysis"]),
        .library(name: "Health", targets: ["Health"]),
        .library(name: "Insights", targets: ["Insights"]),
        .library(name: "Plan", targets: ["Plan"]),
        .library(name: "Coaching", targets: ["Coaching"]),
        .library(name: "Content", targets: ["Content"]),
    ],
    targets: [
        // Shared types between modules. Changes only with team agreement.
        .target(name: "Contracts"),
        .target(name: "DesignSystem", dependencies: ["Contracts"]),
        // Bartek: pose extraction, quality gate, reps, scoring.
        .target(name: "Analysis", dependencies: ["Contracts"]),
        // Wiktor: HealthKit, check-in storage, sample recovery data.
        .target(name: "Health", dependencies: ["Contracts"]),
        // Wiktor: rule engine, plan adjuster, care pathway.
        .target(name: "Insights", dependencies: ["Contracts"]),
        // Maciek: plan generation, validation, templates.
        .target(name: "Plan", dependencies: ["Contracts", "Content"]),
        // Maciek: API client, tools, chat.
        .target(name: "Coaching", dependencies: ["Contracts", "Plan", "Content"]),
        // Maciek: exercise catalog and texts.
        .target(name: "Content", dependencies: ["Contracts"]),
        .testTarget(name: "ContractsTests", dependencies: ["Contracts"]),
    ]
)
