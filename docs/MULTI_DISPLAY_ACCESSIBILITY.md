# Multi-display and accessibility verification — 2026-10-14

## Environment

| Display | Logical frame size | Backing scale | Global origin |
| --- | --- | --- | --- |
| Built-in Retina Display | 1710 × 1112 | 2× | (0, 0) |
| DELL SE2216H | 1920 × 1080 | 1× | (-5760, -68) |
| MSI MP273U | 3840 × 2160 | 1× | (-3840, -542) |

The same production controller is reused for two complete display routes.
Each display is exercised in both LTR and RTL. Display selection is explicit;
the check does not move the desktop pointer or change the system language.
Fixtures are stored under `/private/tmp/`; normal user layout is untouched.

## Findings and changes

Transparent tile buttons had names and working press actions, but did not
explicitly expose their accessibility element status and button role. The shared
tile initializer now sets both. The display/keyboard/accessibility matrix
confirms names, roles, element status and real folder press behavior after repair.

The controller now accepts an explicit target screen through `showWindow(on:)`.
Existing launcher invocation still chooses the mouse display as before. Both
paths use the same display preparation, activation and menu-backdrop lifecycle.

The initial test also had two invalid assumptions: the first folder arrow should
select item zero (rather than move to item one), and search should use a discovered
app name instead of assuming a particular installed app. The corrected check
verifies both initial selection and the next directional step.

## Results

- Reduce Motion enabled: 361 assertions, zero failures across all three displays,
  both directions, and two passes. The user enabled the actual system setting;
  it was not simulated.
- Enabled checks include immediate launcher/folder presentation and folder paging
  without motion animations, plus icon/hit-target geometry, menu coverage,
  keyboard selection, Enter/Escape, Page Up/Down, accessibility press, search
  reset, unchanged persistence, and idle resource release.
- Menu-bar opening check with Reduce Motion enabled: 12 assertions, zero failures.
- Wallpaper canvas: 429 assertions, zero failures.
- Mixed-scale icon cache: 16 assertions passed.
- Core unit suite: 187 tests passed.
- Release build and strict SwiftLint passed.
- General animation mode: 331 assertions, zero failures across the same matrix.
  The user restored Reduce Motion to disabled before this run.
- Menu-bar opening check in general animation mode: 26 assertions, zero failures.
- Together the two display matrices cover 692 assertions, with no failures.

## Scope

These checks validate actual AppKit windows, geometry and accessibility API
semantics/actions. They do not establish spoken VoiceOver behavior, visual icon
sharpness from screenshots, physical cable hot-plug behavior, or real trackpad
input on every screen. An initial graphical run was interrupted while System
Settings was activated and is not counted as a successful complete run.

The reproducible command is in `Tests/Runtime/README.md`. Raw logs are at
`/tmp/launchpane-multi-display-accessibility-reduced.log`,
`/tmp/launchpane-accessibility-reduced-menu.log`, and
`/tmp/launchpane-accessibility-{WallpaperCanvasCheck,IconCacheScaleCheck}.log`,
`/tmp/launchpane-accessibility-normal-MultiDisplayAccessibilityCheck.log`, and
`/tmp/launchpane-accessibility-normal-MenuBarOpeningAnimationCheck.log`.
