# Fixtures

JSON dumps of `[PoseFrame]`, one file per recorded squat video (good and bad reps), used by
`QualityGate`/`RepAnalyzer`/`TechniqueScorer` tests so those tests don't need the actual video files.

Still empty: needs 5–8 real side-view squat recordings (PROJECT.md 6.1), including a few bad ones
(too shallow, too much lean, person too small in frame). Record on an iPhone, then for each video run
`VisionPoseExtractor.extract(from:)` once and dump the result as JSON into this folder, named for what
the clip shows, e.g. `good_depth.json`, `shallow_squat.json`, `too_far_from_camera.json`.
