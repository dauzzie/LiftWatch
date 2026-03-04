# LiftWatch

Simple paired iOS + watchOS workout logger.

## What it does

- Log exercise name
- Pick an SF Symbol for the exercise
- Enter reps, weight, and sets
- Sync logs between iPhone and Apple Watch using `WatchConnectivity`

## Generate and run

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) if needed.
2. From this folder run:

```bash
xcodegen generate
open LiftWatch.xcodeproj
```

3. In Xcode:
- Select the `LiftWatch` scheme.
- Run on an iPhone simulator/device.
- Pair a watch simulator/device and run the watch target.

## Project layout

- `Shared/`: model, store, watch/phone sync manager
- `iOS/`: iPhone app UI
- `Watch/`: watch extension SwiftUI UI
- `project.yml`: XcodeGen project spec
