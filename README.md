# Flint

A small Raycast-style application launcher built with AppKit for macOS 13 and later. No external dependencies.

The launcher uses untinted Liquid Glass on macOS 26 and later, with a frosted material on older versions. Both panel states use the same glass surface, and the launcher and Settings follow the system’s light or dark appearance. The empty search bar is a compact capsule that expands to show results as you type. Expanding and collapsing animate from the same top edge with a consistent 28-point corner radius. Reduce Motion disables the transition.

Each opening restores the launcher above the center of the display under the pointer, leaving room for the expanded results. Its top edge stays fixed while typing or clearing a search. Dragging the background does not move the launcher.

The launcher fades in when shown and fades out when dismissed, including with Escape, the launcher shortcut, and clicking away. Reduce Motion disables these fades.

## Run

Open `Flint.xcodeproj`, select the **Flint** scheme, and run on **My Mac**. Local builds use ad hoc signing so macOS can register Flint as a login item.

Or build and open from the terminal:

```sh
xcodebuild -project Flint.xcodeproj -scheme Flint -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Flint.app
```

To keep the launcher visible when it loses focus, quit Flint first and launch it with `--keep-open`:

```sh
open build/Build/Products/Debug/Flint.app --args --keep-open
```

Escape and your configured launcher shortcut still hide the launcher. Opening an application also dismisses it. In Xcode, add `--keep-open` under **Edit Scheme → Run → Arguments Passed On Launch** for the same behavior.

## Applications

Flint discovers installed applications in `/Applications`, `~/Applications`, `/System/Applications`, system CoreServices applications, and the system Cryptex applications folder. It includes category folders such as Utilities, skips apps embedded inside other apps, and deduplicates applications by bundle identifier. Discovery runs off the main thread, while native app icons load only for displayed rows.

The launcher opens as a compact search bar. Type to expand the application results; clearing the input collapses it again. Whitespace-only input also keeps it collapsed. Search ignores case and diacritics and supports abbreviations such as `vsc` for Visual Studio Code. Exact names rank before prefixes, substrings, and abbreviation matches. Click an app or press Return to open it.

| Shortcut | Action |
| --- | --- |
| Command–Space | Show or hide Flint |
| Up / Down | Select the previous / next result |
| Return | Open the selected app or run the selected action |
| Escape | Hide Flint |
| Command–R | Refresh installed applications |

Flint also has a flame icon in the menu bar with **Show Flint**, **Settings…**, and **Quit Flint** actions. If another app has reserved the launcher shortcut, use the menu bar to open Flint. Clicking outside the launcher dismisses it.

## Actions

Search for **Eject All Disks**, **Empty Trash**, or **Show Desktop**, then click the result or press Return. Actions appear alongside applications with an **Action** label and a **Run Action** button.

**Eject All Disks** safely ejects removable or ejectable volumes, including external disks and disk images, and excludes internal volumes. It attempts every disk and reports any failures, such as a disk being in use. **Empty Trash** asks for confirmation before permanently deleting items through Finder; macOS may request permission for Flint to control Finder. **Show Desktop** uses Mission Control’s desktop mode without depending on your keyboard shortcut. Successful actions dismiss Flint.

Dialogs use untinted regular Liquid Glass on macOS 26 and later, with a standard popover material on older versions, and dim only the inside of the rounded launcher. Native macOS push buttons show Escape and Return key hints: Escape cancels and Return confirms (or acknowledges an error). Keyboard hints use consistent rounded rectangle outlines and symbols in the launcher footer, dialogs, and Settings shortcut reference. Labeled hints keep a consistent gap between the action text and the outlined key. Each key runs its labeled action directly; dialog buttons have no selection or navigation state. Closing a dialog returns focus to search. Action icons are smaller than application icons while keeping the result text aligned.

## Settings

Settings uses a resizable sidebar layout with **General** for shortcut preferences and **Shortcuts** for the available keyboard commands. It follows the system’s light or dark appearance.

Turn on **Launch at login** in General to start Flint automatically in the menu bar when you log in. Login launches keep the launcher hidden until you use the shortcut or menu. The switch reflects macOS’s login-item status; if approval is required, use **Open Login Items…** to allow Flint in System Settings. Turn the switch off to remove the login item.

Open Settings with **Command–Comma**, the gear button in the launcher footer, or **Settings…** in the flame menu. Click the shortcut button and press your own key combination. Use Command, Option, or Control with a key (and optionally Shift), or a function key such as F6. Escape cancels recording, and Tab leaves the recorder. Recording also cancels if Settings loses focus or closes. The active launcher hotkey is temporarily suspended during recording so you can record the same combination again.

Changes apply immediately, update the menu shortcut, and persist between launches. Previously saved shortcuts carry over. **Restore Default** returns to Command–Space. A registration failure is shown in Settings and keeps the previous preference selected.

The `--keep-open` argument is a testing option only; it is not shown or saved in Settings.

## Checks

The discovery and search code is also a standalone Swift package:

```sh
swift test
sh scripts/check-appearance.sh
cognitive --threshold 15 Sources Flint Tests
```

This version contains application search and launching, system actions, and shortcut settings.
