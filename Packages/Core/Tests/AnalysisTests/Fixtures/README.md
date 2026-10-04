# Fixtures

JSON dumps of `[PoseFrame]` read once from real recordings with `VisionPoseExtractor.extract(from:)`, so the analysis
tests (`ClipRepDetector`, `RepAnalyzer`, `QualityGate`, `TechniqueScorer`) pin behaviour on real people without the
video files. Poses only, no pictures: the videos never go into the repo.

## What is here

- `dips/dip_clip_3025.json`, `dip_clip_3026.json`, `dip_clip_3027.json`: three recordings of three different people
  (side view, parallel bars, iPhone), thinned to 10 frames per second, each frame with its `aspect` (width / height of
  the picture). `DipTests` uses them: the expected repetitions are 7, 6 and 5 (what a person watching the clip counts;
  the first seconds of 3025 are the person climbing onto the bars, which is not a repetition).

## Still missing

Real side-view recordings of a **squat** (good and bad: too shallow, too much lean, person too small in the frame),
a **push-up** and a **pull-up** (PROJECT.md 6.1). Until they are here, those exercises are tested on synthetic poses of
known angles (`RepAnalyzerTests`, `TechniqueScorerTests`, the live-set tests), which pins the geometry but not what
Apple Vision really returns for a person.

## Adding a clip

Record on an iPhone, run `VisionPoseExtractor.extract(from:)` once on the file, thin the result to about 10 frames per
second (keep `aspect`), dump the `[PoseFrame]` as JSON into a folder named for the exercise (`squat/`, `pushup/`, ...)
and name the file for what the clip shows (`good_depth.json`, `shallow_squat.json`, `too_far_from_camera.json`). Write
down in the test what a person counts in the clip, not what the code returns.
