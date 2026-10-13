# Quick Notes development workflow

- Use the existing Swift source and preserve the user's real notes at `~/Library/Application Support/Quick Notes/notes.json`.
- For Quick Notes changes, run `bash Scripts/verify_app.sh` before reporting a completed build. It uses SwiftLint installed on SSK Drive, builds a release binary, and runs isolated smoke tests. It does not install the app or modify real notes.
- The installed tool is `/Volumes/SSK Drive/Applications/Developer Tools/SwiftLint/0.65.1/swiftlint`. If SSK Drive is disconnected, run the available build and smoke tests, then report that lint could not run. Do not silently install another copy on the internal drive.
- `xcrun swift-format lint <changed Swift files>` is available from Apple's existing Command Line Tools. Use it when reviewing touched files. Do not format unrelated files or automatically rewrite the repository.
- `swift test` currently cannot load XCTest from Command Line Tools alone. Use the project smoke scripts until a full Xcode installation is available; do not report `swift test` as passed.
- UI tests must use an isolated `QUICK_NOTES_DATA_DIRECTORY`; avoid moving focus to Quick Notes while the user is working unless the user requests a live UI test.
- Keep the installed app name `Quick Notes` and bundle ID `com.vladikmartinez.quicknotes`. Confirm the installed bundle version and preserve notes when installing an update.
- Before publishing Quick Notes, verify that this checkout's `origin` is `https://github.com/vladmax01-cyber/QuickNotes.git` and that the intended branch is `main`. Do not create or publish a second repository for this app.
