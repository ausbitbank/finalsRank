# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.0] - 2026-11-06

First public release.

### Added

- DankBar pill and desktop card for THE FINALS leaderboard rank, score and season
  countdown.
- Percentile, movement over a configurable window, points-per-day and trend
  sparklines for score and rank.
- Locally recorded history with deduplication, retention and a career-best
  season summary.
- Live rank and score with an upstream fallback during season rollovers.
- Optional desktop notifications when the rank changes.
- Offline tests and an optional live network check.

### Changed

- The player name is now empty by default; a fresh install prompts for one
  instead of displaying a hard-coded player.
- Requests identify the plugin with a descriptive user agent.
- Refresh interval is consistently floored at 5 minutes.
- The bundled logo is documented as a trademark used only for identification.

### Fixed

- Board and platform settings are validated before being used in request paths.
- History writes are JSON-escaped, so a quote in a setting cannot corrupt the
  file.
- Removed personal player names, live rank figures and machine-specific paths
  from the documentation and test harness.
