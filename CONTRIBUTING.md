# Contributing to OpenEQ

Thank you for your interest in contributing to OpenEQ! As an open-source project, we welcome improvements, bug fixes, and suggestions from the community.

## Code of Conduct
By participating in this project, you agree to abide by the standard conventions of open-source cooperation: maintain respectful behavior, construct constructive feedback, and collaborate in good faith.

## How to Contribute
### 1. Reporting Bugs
If you find a bug or experience a crash:
- Open a GitHub issue.
- Describe the unexpected behavior, steps to reproduce, and attach logs or system crash details if available.
- Mention your macOS and Xcode version.

### 2. Suggesting Enhancements
We welcome ideas for new features! Create an issue detailing:
- The problem you want to solve.
- Your proposed solution (e.g. system-wide audio routing, specific DSP additions).
- Why this enhancement would benefit other OpenEQ users.

### 3. Submitting Pull Requests
Follow these steps to submit code changes:
1. **Fork** the repository and create your branch from `main`:
   ```bash
   git checkout -b feature/your-awesome-feature
   ```
2. Make your changes and document your code. Keep commits clean and descriptive.
3. Ensure the project builds cleanly without errors or warnings:
   ```bash
   xcodebuild -scheme OpenEQ -destination 'platform=macOS' build
   ```
4. Push your branch to your fork and submit a **Pull Request** targeting OpenEQ's `main` branch.

## Coding Style Guidelines
- **Swift Conventions**: Follow standard API design guidelines (pascal-cased types, camel-cased variables, short descriptive comments).
- **MVVM Isolation**: Keep the Views clean. Do not put business logic or persistence operations inside SwiftUI Views. Route actions through the ViewModels.
- **Audio Thread Safety**: Never allocate memory or block threads inside time-critical callbacks (such as audio mixer taps or DSP loops). Perform FFT calculations on background utility queues and publish results thread-safely onto `DispatchQueue.main`.
