# Apple HIG review

A review of every surface against Apple's Human Interface Guidelines, using the rules the
sibling project OpenWritr keeps in `.github/instructions/apple-hig-review.instructions.md`
(native controls, menu-bar conventions, keyboard access, VoiceOver names, semantic colours,
Reduce Motion, alerts and destructive actions, ellipses, Settings organisation, state
handling, privacy at the point of use). OpenWritr runs it as an automated pull-request review
that needs a Copilot token; this repository allows no secret in a workflow (`AGENTS.md`), so
it is run by hand.

## Method (2026-09-21)

1. The production SwiftUI views were rendered offscreen (an `NSHostingView` in a throwaway
   SwiftPM harness, sample windows, synthetic previews): Settings (all tabs), About, the
   switcher (normal, filtered, empty), the Dock preview and the menu contents, in light, dark
   and High Contrast appearances.
2. An independent reviewer, not the author, read the sources and looked at every image
   against the rules, reporting only high-confidence, actionable findings.
3. Each finding was checked against the source before any change, and the accessibility tree
   of the tiles was read back from the rendered view to confirm the fix.

## Findings and what was done

| # | Finding | Result |
| --- | --- | --- |
| 1 | "Restore the shipped defaults" overwrote every rule in one click | Fixed: a confirmation dialog with a destructive button and Cancel. Deleting a single rule stays immediate: it is one row and re-adding it is one entry. |
| 2 | Tile state (minimized, application with no windows) existed only as a tooltip icon | Fixed: spoken as the tile's value and hint; the marks are hidden from assistive technology. |
| 3 | Close and quit controls exist only under the pointer, so they are unreachable for VoiceOver and keyboard | Fixed for assistive technology: the tile is one button with "Close window" and "Quit application" as actions. The on-tile controls stay hover-only, which `AGENTS.md` records as deliberate. No new keyboard shortcut was added. |
| 4 | Orange warning and green "Granted" text below legible contrast on the light background | Fixed: the tint stays on the icon, the text is the standard colour. |
| 5 | Permission rows did not say what is read or that it stays on the Mac | Fixed: one sentence on each row. |
| 6 | The window count was a bare number, and decorative symbols had no treatment | Fixed: announced as "N windows", symbols hidden. |
| 7 | An ellipsis on "Check for Updates", which acts at once | Fixed, following the rule. "Settings…" keeps its ellipsis, which is the macOS convention for opening Settings. |

## What was not verified

Nothing here was checked with VoiceOver on a live desktop, so it is not known how the
non-activating panels are exposed to it in practice; only the accessibility tree of the
rendered views was read. The live menu-bar menu (placement, key equivalents), focus rings
and tab order in Settings, the Permissions tab in the not-granted state, German text fit in
the fixed Settings window, and Reduce Motion and Reduce Transparency at runtime were not
exercised. The offscreen High Contrast render did not visibly differ from the standard one,
so the Increase Contrast path is covered by its unit tests and by reading the code, not by an
image.
