import Foundation

/// Sample data for "Anna" (28, trains 3-4x a week, no trainer). Matches the clickable prototype.
/// Everything here is simulated: the UI must show the "Dane przykładowe" badge when it uses it.
public enum SampleData {
    private static func daysAgo(_ n: Int) -> Date {
        let today = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .day, value: -n, to: today) ?? today
    }

    public static let profile = UserProfile(
        goal: .strength, level: .intermediate, daysPerWeek: 3, sessionMinutes: 60,
        equipment: .dumbbells, avoid: "Uważam na prawe kolano"
    )

    /// 14 days, newest first. Today: short sleep, low HRV, raised resting heart rate.
    public static let recovery: [RecoverySnapshot] = {
        let sleep = [340, 410, 450, 430, 395, 460, 470, 420, 445, 455, 430, 440, 465, 450]
        let hrv = [38, 44, 47, 46, 45, 49, 48, 47, 46, 45, 47, 46, 48, 46]
        let rhr = [61, 58, 56, 57, 57, 55, 56, 57, 56, 56, 55, 57, 56, 56]
        return (0..<14).map { i in
            RecoverySnapshot(date: daysAgo(i), sleepMinutes: sleep[i], restingHeartRate: rhr[i], hrvMs: hrv[i],
                             restingHeartRateBaseline: 56, hrvBaselineMs: 46, isSimulated: true)
        }
    }()

    public static var today: RecoverySnapshot { recovery[0] }

    public static let checkIn = CheckIn(date: daysAgo(0), mood: 3, stress: 4, energy: 3)

    public static let technique = TechniqueResult(
        exerciseId: "squat",
        date: daysAgo(0),
        score: 72,
        componentScores: ["depth": 88, "torso": 58, "repeatability": 76, "tempo": 70],
        findings: [
            TechniqueFinding(id: "torso_lean_high", title: "Pochylenie tułowia",
                             detail: "Tułów pochyla się za bardzo w najniższym punkcie. Zwróć uwagę na wyprostowane plecy i klatkę do przodu.",
                             severity: .major, repsAffected: 3, repsTotal: 5),
            TechniqueFinding(id: "depth_ok", title: "Głębokość",
                             detail: "Biodra schodzą poniżej kolan we wszystkich powtórzeniach.",
                             severity: .good, repsAffected: 0, repsTotal: 5),
        ],
        reps: (1...5).map { i in
            RepMetrics(index: i, minKneeAngle: 84 + Double(i % 3), hipBelowKnee: true,
                       torsoLeanDegrees: i <= 3 ? 48 : 36, descentSeconds: 1.8, ascentSeconds: 1.2)
        },
        substituteExerciseId: "goblet_squat",
        isSimulated: true
    )

    public static let recommendation = DailyRecommendation(
        date: daysAgo(0),
        decision: .adapt,
        headline: "Dziś lżejszy trening nóg",
        factors: [
            RecommendationFactor(source: .sleep, text: "Sen 5 h 40 min", isNegative: true),
            RecommendationFactor(source: .hrv, text: "HRV 38 ms, poniżej twojej średniej", isNegative: true),
            RecommendationFactor(source: .checkIn, text: "Stres 4/5", isNegative: true),
            RecommendationFactor(source: .technique, text: "Przysiad: pochylenie tułowia w 3 z 5 powtórzeń", isNegative: true),
        ],
        suggestedAction: "3 serie zamiast 4, przysiad kielichowy zamiast sztangi.",
        isSimulated: true
    )

    public static let catalog: [ExerciseItem] = [
        ExerciseItem(id: "squat", name: "Przysiad", muscleGroup: "Nogi", equipment: .dumbbells, level: .intermediate,
                     summary: "Podstawowy wzorzec ruchu dla nóg i pośladków.",
                     substituteIds: ["goblet_squat", "box_squat"], supportsAnalysis: true),
        ExerciseItem(id: "goblet_squat", name: "Przysiad kielichowy", muscleGroup: "Nogi", equipment: .dumbbells, level: .beginner,
                     summary: "Przysiad z hantlem przy klatce. Pomaga utrzymać wyprostowany tułów.",
                     substituteIds: ["box_squat"]),
        ExerciseItem(id: "box_squat", name: "Przysiad do pudła", muscleGroup: "Nogi", equipment: .none, level: .beginner,
                     summary: "Przysiad z dotknięciem ławki. Pomaga kontrolować głębokość.",
                     substituteIds: ["goblet_squat"]),
        ExerciseItem(id: "romanian_deadlift", name: "Martwy ciąg rumuński", muscleGroup: "Tył uda", equipment: .dumbbells, level: .intermediate,
                     summary: "Zawias biodrowy z lekko ugiętymi kolanami.", substituteIds: ["hip_thrust"]),
        ExerciseItem(id: "lunge", name: "Wykrok", muscleGroup: "Nogi", equipment: .none, level: .beginner,
                     summary: "Krok w przód z opuszczeniem biodra.", substituteIds: ["box_squat"]),
        ExerciseItem(id: "hip_thrust", name: "Mostek biodrowy", muscleGroup: "Pośladki", equipment: .none, level: .beginner,
                     summary: "Unoszenie bioder z podparciem górnej części pleców.", substituteIds: []),
        ExerciseItem(id: "pushup", name: "Pompka", muscleGroup: "Klatka, barki", equipment: .none, level: .beginner,
                     summary: "Pompka z prostym ciałem.", substituteIds: []),
        ExerciseItem(id: "dumbbell_row", name: "Wiosłowanie z hantlem", muscleGroup: "Plecy", equipment: .dumbbells, level: .beginner,
                     summary: "Przyciąganie hantla do biodra w podporze.", substituteIds: []),
        ExerciseItem(id: "overhead_press", name: "Wyciskanie nad głowę", muscleGroup: "Barki", equipment: .dumbbells, level: .intermediate,
                     summary: "Wyciskanie hantli nad głowę w staniu.", substituteIds: []),
        ExerciseItem(id: "plank", name: "Plank", muscleGroup: "Brzuch", equipment: .none, level: .beginner,
                     summary: "Podpór na przedramionach z prostym ciałem.", substituteIds: []),
    ]

    public static let plan = TrainingPlan(
        createdAt: daysAgo(3),
        source: .template,
        sessions: [
            PlannedSession(weekday: 1, title: "Nogi", exercises: [
                PlannedExercise(exerciseId: "squat", sets: 4, repsMin: 6, repsMax: 8, restSeconds: 120),
                PlannedExercise(exerciseId: "romanian_deadlift", sets: 3, repsMin: 8, repsMax: 10, restSeconds: 90),
                PlannedExercise(exerciseId: "lunge", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 60),
                PlannedExercise(exerciseId: "plank", sets: 3, repsMin: 30, repsMax: 45, restSeconds: 45),
            ]),
            PlannedSession(weekday: 3, title: "Góra", exercises: [
                PlannedExercise(exerciseId: "overhead_press", sets: 4, repsMin: 6, repsMax: 8, restSeconds: 90),
                PlannedExercise(exerciseId: "dumbbell_row", sets: 4, repsMin: 8, repsMax: 10, restSeconds: 90),
                PlannedExercise(exerciseId: "pushup", sets: 3, repsMin: 10, repsMax: 15, restSeconds: 60),
            ]),
            PlannedSession(weekday: 5, title: "Całe ciało", exercises: [
                PlannedExercise(exerciseId: "goblet_squat", sets: 3, repsMin: 8, repsMax: 12, restSeconds: 90),
                PlannedExercise(exerciseId: "hip_thrust", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 60),
                PlannedExercise(exerciseId: "dumbbell_row", sets: 3, repsMin: 8, repsMax: 10, restSeconds: 90),
                PlannedExercise(exerciseId: "plank", sets: 3, repsMin: 30, repsMax: 45, restSeconds: 45),
            ]),
        ]
    )
}
