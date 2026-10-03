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
        .library(name: "LiveSet", targets: ["LiveSet"]),
        .library(name: "Onboarding", targets: ["Onboarding"]),
        .library(name: "API", targets: ["API"]),
    ],
    targets: [
        // Shared types between modules. Changes only with team agreement.
        .target(name: "Contracts"),
        .target(name: "DesignSystem", dependencies: ["Contracts"]),
        // Bartek: pose extraction from video files, quality gate, reps, scoring. May reuse LiveSet (PhaseTracker, SquatSignal).
        .target(name: "Analysis", dependencies: ["Contracts", "LiveSet"], resources: [.process("Resources")]),
        // Wiktor: HealthKit, check-in storage, sample recovery data.
        .target(name: "Health", dependencies: ["Contracts"]),
        // Wiktor: rule engine, plan adjuster, care pathway.
        .target(name: "Insights", dependencies: ["Contracts"]),
        // Maciek: plan generation, validation, templates.
        .target(name: "Plan", dependencies: ["Contracts", "Content"], resources: [.process("Resources")]),
        // Maciek: API client, tools, chat.
        .target(name: "Coaching", dependencies: ["Contracts", "Plan", "Content"]),
        // Maciek: exercise catalog and texts.
        .target(name: "Content", dependencies: ["Contracts", "API"], resources: [.process("Resources")]),
        // Michał: live set coaching (camera pose, tempo engine, voice cues, set summary).
        .target(name: "LiveSet", dependencies: ["Contracts"]),
        // Test targets exist for every module so nobody has to edit this file to add tests.
        // Michał: first-run flow (profile, health history kept on the phone, plan generation step).
        .target(name: "Onboarding", dependencies: ["Contracts"]),
        // Michał: client of the backend (backend/): HTTP, auth headers, SSE chat stream, ETag content fetch.
        .target(name: "API", dependencies: ["Contracts"]),
        .testTarget(name: "ContractsTests", dependencies: ["Contracts"]),
        .testTarget(name: "OnboardingTests", dependencies: ["Onboarding", "Contracts"]),
        .testTarget(name: "LiveSetTests", dependencies: ["LiveSet", "Contracts"]),
        .testTarget(name: "AnalysisTests", dependencies: ["Analysis", "Contracts"]),
        .testTarget(name: "HealthTests", dependencies: ["Health", "Contracts"]),
        .testTarget(name: "InsightsTests", dependencies: ["Insights", "Contracts"]),
        .testTarget(name: "PlanTests", dependencies: ["Plan", "Content", "Contracts"]),
        .testTarget(name: "CoachingTests", dependencies: ["Coaching", "Plan", "Content", "Contracts"]),
        .testTarget(name: "ContentTests", dependencies: ["Content", "Contracts"]),
    ]
)
