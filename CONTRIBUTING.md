# Contributing to debian-btrfs-boot

Thanks for your interest in contributing! 🎉

## Ways to contribute
- Report bugs using GitHub Issues
- Suggest enhancements using GitHub Issues
- Submit Pull Requests (PRs) with improvements or fixes

## Development setup
1) Clone via SSH:
   git clone git@github.com:dwilliam62/debian-btrfs-boot.git
   cd debian-btrfs-boot

2) Try a dry run of the script (safe preview):
   ./debian-btrfs-boot.sh --dry-run

## Pull request process
- Create a feature branch from main:
  git checkout -b feat/short-description
- Follow the style of the project (shell script with clear logging and safety checks).
- Ensure the script runs shellcheck clean, if available.
- Include tests or a dry-run demonstration in your PR description when possible.
- Update documentation as needed (README.me, Plan*.md) and keep examples accurate.

## Commit message conventions (suggested)
Use conventional commit-like prefixes:
- feat: new user-facing feature
- fix: bug fix
- docs: documentation only changes
- refactor: code refactor without functional change
- chore: tooling or maintenance changes

## Code of Conduct
By participating, you agree to abide by our Code of Conduct. See CODE_OF_CONDUCT.md.

## Licensing
By contributing, you agree that your contributions will be licensed under the MIT License, as specified in LICENSE.

