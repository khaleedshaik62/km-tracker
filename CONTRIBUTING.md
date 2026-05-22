# Contributing to KM Tracker

First off, thank you for considering contributing to KM Tracker! It's people like you that make it such a great tool.

## Code of Conduct

This project and everyone participating in it is governed by our Code of Conduct. By participating, you are expected to uphold this code.

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check the issue list as you might find out that you don't need to create one. When you are creating a bug report, please include as many details as possible:

- **Use a clear and descriptive title**
- **Describe the exact steps which reproduce the problem**
- **Provide specific examples to demonstrate the steps**
- **Describe the behavior you observed after following the steps**
- **Explain which behavior you expected to see instead and why**
- **Include screenshots and animated GIFs if possible**
- **Include your environment details** (Flutter version, Dart version, OS, etc.)

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. When creating an enhancement suggestion, please include:

- **Use a clear and descriptive title**
- **Provide a step-by-step description of the suggested enhancement**
- **Provide specific examples to demonstrate the steps**
- **Describe the current behavior** and **the expected behavior**
- **Explain why this enhancement would be useful**

### Pull Requests

- Fill in the required template
- Follow the Dart/Flutter styleguides
- Include appropriate test cases
- Update documentation as needed
- End all files with a newline

## Styleguides

### Git Commit Messages

- Use the present tense ("Add feature" not "Added feature")
- Use the imperative mood ("Move cursor to..." not "Moves cursor to...")
- Limit the first line to 72 characters or less
- Reference issues and pull requests liberally after the first line
- Consider starting the commit message with an applicable emoji:
  - 🎨 when improving the format/structure of the code
  - 🐛 when fixing a bug
  - ✨ when introducing a new feature
  - 📝 when writing docs
  - ♻️ when refactoring code
  - ⚡️ when improving performance
  - ✅ when adding tests
  - 🔒️ when dealing with security
  - ⬆️ when upgrading dependencies
  - ⬇️ when downgrading dependencies

### Dart/Flutter Styleguide

All Dart code is linted with the following configuration from `analysis_options.yaml`:

- Use meaningful variable and function names
- Add documentation comments for public APIs
- Follow the official Dart style guide
- Use `dart format` to format your code
- Run `dart analyze` to check for issues

Example:

```dart
/// Calculates the distance between two GPS coordinates.
///
/// [lat1], [lon1]: Starting point coordinates
/// [lat2], [lon2]: Ending point coordinates
///
/// Returns the distance in kilometers.
double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
  // Implementation
}
```

## Additional Notes

### Issue and Pull Request Labels

- `bug` - Something isn't working
- `enhancement` - New feature or request
- `documentation` - Improvements or additions to documentation
- `good first issue` - Good for newcomers
- `help wanted` - Extra attention is needed
- `question` - Further information is requested
- `wontfix` - This will not be worked on

## Development Setup

1. Fork and clone the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Make your changes
4. Run tests: `flutter test`
5. Format code: `dart format lib/`
6. Check for issues: `dart analyze`
7. Commit with a meaningful message
8. Push to your fork and submit a pull request

## Community

- Join our discussions on [GitHub](https://github.com/khaleedshaik62/km-tracker/discussions)
- Ask questions on [GitHub Issues](https://github.com/khaleedshaik62/km-tracker/issues)

Thank you for your contributions! 🚀
