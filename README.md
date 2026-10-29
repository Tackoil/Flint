# Flint

A small Raycast-style application launcher built with AppKit for macOS 13 and later. No external dependencies.

The launcher uses untinted Liquid Glass on macOS 26 and later, with a frosted material on older versions. Both panel states use the same glass surface, and the launcher and Settings follow the system’s light or dark appearance. The empty search bar is a compact capsule that expands to show results as you type. Expanding and collapsing animate from the same top edge with a consistent 28-point corner radius. Reduce Motion disables the transition.

Each opening restores the launcher above the center of the display under the pointer, leaving room for the expanded results. Its top edge stays fixed while typing or clearing a search. Dragging the background does not move the launcher.

By default, whenever Flint opens or regains focus, it switches the system keyboard input source to **ABC** so you can search immediately. Turn off **Switch to ABC** in **Settings → General** to keep your current input method. The setting applies immediately and remembers your choice between launches. ABC must be enabled in macOS Input Sources; if it is unavailable, Flint keeps the current input source.

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

Flint discovers installed applications in `/Applications`, `~/Applications`, `/System/Applications`, system CoreServices applications, and the system Cryptex applications folder. It also includes Finder from `/System/Library/CoreServices/Finder.app`. It includes category folders such as Utilities, skips apps embedded inside other apps, and deduplicates applications by bundle identifier. Discovery runs off the main thread, while native app icons load only for displayed rows.

The launcher opens as a compact search bar. Type to expand the application results; clearing the input collapses it again. Whitespace-only input also keeps it collapsed. Search ignores case and diacritics and supports abbreviations such as `vsc` for Visual Studio Code. Exact names rank before prefixes, substrings, and abbreviation matches. Click an app or press Return to open it. If launching fails, Flint dismisses the launcher and sends a macOS notification with the application name and error details. Application and action errors share the same notification permission.

| Shortcut | Action |
| --- | --- |
| Command–Space | Show or hide Flint |
| Up / Down | Select the previous / next result |
| Return | Open the selected app or run the selected action |
| Escape | Hide Flint |
| Command–R | Refresh installed applications |

Flint also has a flame icon in the menu bar with **Show Flint**, **Settings…**, and **Quit Flint** actions. If another app has reserved the launcher shortcut, use the menu bar to open Flint. Clicking outside the launcher dismisses it.

## Calculator

Type a complete, valid calculation directly into search to see the answer. Arithmetic requires an operation, such as `3 + 2` or `15%`. Non-negative integers such as `3` and `1710513000` convert from Unix seconds to Zulu timestamps; values such as `0.5`, `-3`, `(3)`, and `1e3` stay in normal search. Incomplete expressions such as `3+`, malformed input, and calculations with errors such as `1/0` also stay in normal search. Press **Return** or click **Copy Answer** on a valid calculation to copy the full, ungrouped result and dismiss Flint.

Calculator mode crossfades the search icon to a calculator and animates to a compact panel while keeping the search bar in place. The expression uses mathematical symbols and spacing, with the same 36-point font size as the answer. Reduce Motion disables these animations.

The calculator supports `+`, `-`, `*`, `/`, parentheses, decimals, negative numbers, powers (`^`), scientific notation (`1e3`), and postfix percentages (`15%` means `0.15`). Multiplication also accepts `×` and `x`; division accepts `÷`. Standard operator precedence applies, and powers associate from the right. For example, `(12 + 8) * 5` is `100`, `0.1 + 0.2` is `0.3`, and `200 * 15%` is `30`. Use explicit multiplication, such as `2 * (3 + 4)`.

Decimal input and displayed number formatting follow the system locale. Clipboard answers use a decimal point with no grouping separators. Calculations run offline using decimal arithmetic, with bounded expression length and nesting; fractional powers use floating-point arithmetic.

Fractional numeric results default to at most **10 decimal places**. A trailing **…** means more digits are available: `3^(-1/2)` starts at `0.5773502692…`. Press **Right Arrow** to reveal one more decimal place, or **Left Arrow** to show one fewer. The marker disappears at the available precision. Short exact fractions keep their natural length without a marker or extra zeros.

The footer describes the rounding position, such as **10 digits after decimal** or **2 digits before decimal**. Moving left past zero decimal places rounds to tens, hundreds, and so on. **Copy Answer** copies the rounded value shown without grouping separators or the continuation marker. Each adjustment uses the original result, so increasing precision restores its digits. Editing the expression resets rounding. Modified arrow shortcuts still edit the input.

Press **Up Arrow** or click **Edit expression ↑** to let Left/Right move the cursor instead of changing precision. Leaving rounding resets the displayed and copied result to the default precision, including the 10-place preview for long fractions. Press **Down Arrow** or click **Round result ↓** to use Left/Right for rounding again, starting from that default. The calculator stays visible. Editing mode stays active as you change the expression, including through unfinished input; reopening Flint starts with rounding enabled again. Normal application search keeps its existing arrow-key behavior.

Scientific notation is used only when the selected significant figures are fewer than the number of digits in the rounded result's integer part. For example, `12345` rounded to three significant figures displays and copies as `1.23E+4`. Small fractions stay in decimal notation. Restoring sufficient precision switches back to ordinary numbers; scientific output keeps trailing zeros needed to show the selected precision.

The calculator converts between ISO 8601 timestamps in Zulu (UTC) format and whole Unix seconds or milliseconds. For example, `2024-03-15T14:30:00Z` shows `1710513000` seconds or `1710513000000` milliseconds. Press **Left Arrow** for seconds and **Right Arrow** for milliseconds. A plain **Unix seconds** or **Unix milliseconds** label beneath the answer indicates the selected unit. The footer shows only the available switch using the shared keyboard hint: **ms →** when seconds are selected, or **s ←** when milliseconds are selected. Both the displayed answer and **Copy Answer** use the selected unit. Press **Return** or click **Copy Answer** to copy it. The choice stays selected while you continue using the launcher. Modified arrows still edit the Zulu input; when converting Unix input to Zulu, Left/Right retain normal cursor movement.

Entering `1710513000` converts seconds to Zulu; `1710513000123` automatically converts milliseconds to `2024-03-15T14:30:00.123Z`. Bare integers are treated as seconds when they fit the supported seconds range, and otherwise as milliseconds. Add `s` or `ms` to specify a unit, with or without a space: `1710513000 s`, `1710513000123ms`, or `1 ms`. This also lets you convert millisecond values near the epoch that would otherwise be interpreted as seconds. The numeric input's unit is shown beneath it.

Your local date and time, including its UTC offset at that instant, appears as a hint beneath the Zulu timestamp in either direction. Zulu timestamps may include up to nine fractional digits; these remain visible in the source and local-time hint. Unix answers use whole seconds or milliseconds, dropping any finer precision without rounding. Unix input must be a non-negative integer, with an optional leading `+`, and resolve to a date earlier than year 10000. Fractional or negative Unix input, Zulu timestamps before `1970-01-01T00:00:00Z`, incomplete timestamps, impossible dates, and timestamps without the `Z` suffix stay in normal search.

## Actions

Search for **Eject All Disks**, **Empty Trash**, or **Show Desktop**, then click the result or press Return. Actions appear alongside applications with an **Action** label and a **Run Action** button.

**Eject All Disks** safely ejects removable or ejectable volumes, including external disks and disk images, and excludes internal volumes. It attempts every disk and reports any failures, such as a disk being in use. **Empty Trash** asks for confirmation before permanently deleting items through Finder; macOS may request permission for Flint to control Finder. An already empty Trash succeeds without requesting deletion. After confirmation, Flint temporarily suppresses Finder’s separate emptying warning, restores your warning preference even if deletion fails, and checks that the Trash is empty. Finder failures remain visible. **Show Desktop** uses Mission Control’s desktop mode without depending on your keyboard shortcut. Actions dismiss Flint before running. Failures send a macOS notification with the action name and error details instead of reopening the launcher. Flint requests notification permission on the first failure; notifications follow your settings in System Settings → Notifications → Flint.

Dialogs use untinted regular Liquid Glass on macOS 26 and later, with a standard popover material on older versions, and dim only the inside of the rounded launcher. Native macOS push buttons show Escape and Return key hints: Escape cancels and Return confirms (or acknowledges an error). Keyboard hints use consistent rounded rectangle outlines and symbols in the launcher footer, dialogs, and Settings launcher shortcut control. Labeled hints keep a consistent gap between the action text and the outlined key. Each key runs its labeled action directly; dialog buttons have no selection or navigation state. Closing a dialog returns focus to search. Action icons are smaller than application icons while keeping the result text aligned.

## Settings

Settings uses a resizable sidebar layout with a compact **General** card for **Open at Login**, **Show in Menu Bar**, **Switch to ABC**, and **Launcher Shortcut**. The launcher shortcut uses the shared keyboard component to show each key as an outlined keycap, with a reset button beside it. Settings follows the system’s light or dark appearance.

Turn on **Open at Login** in General to start Flint automatically when you log in. Login launches keep the launcher hidden until you use the shortcut or menu. The switch reflects macOS’s login-item status; if approval is required, use **Open Login Items…** to allow Flint in System Settings. Turn the switch off to remove the login item. **Show in Menu Bar** controls the flame icon and remembers your choice between launches. When hidden, you can still open Flint with its shortcut or by launching the app, and open Settings with Command–Comma.

Open Settings with **Command–Comma**, the gear button in the launcher footer, or **Settings…** in the flame menu. Click the shortcut button and press your own key combination. Use Command, Option, or Control with a key (and optionally Shift), or a function key such as F6. Escape cancels recording, and Tab leaves the recorder. Recording also cancels if Settings loses focus or closes. The active launcher hotkey is temporarily suspended during recording so you can record the same combination again.

Close Settings with **Command–W** or the red close button. Flint keeps running so you can open the launcher again.

Changes apply immediately, update the menu shortcut, and persist between launches. Previously saved shortcuts carry over. The reset button beside the shortcut returns to Command–Space. A registration failure is shown in Settings and keeps the previous preference selected.

The `--keep-open` argument is a testing option only; it is not shown or saved in Settings.

## Checks

The discovery and search code is also a standalone Swift package:

```sh
swift test
sh scripts/check-appearance.sh
cognitive --threshold 15 Sources Flint Tests
```

This version contains application search and launching, numeric calculations, system actions, and shortcut settings.
