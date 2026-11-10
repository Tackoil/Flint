# Flint

![Flint — Application launcher for macOS](design/readme-banner.png)

A small Raycast-style application launcher built with AppKit for macOS 13 and later. No external dependencies.

The launcher uses untinted Liquid Glass on macOS 26 and later, with a frosted material on older versions. Both panel states use the same glass surface, and the launcher and Settings follow the system’s light or dark appearance. The empty search bar is a compact capsule that expands to show results as you type. Expanding and collapsing animate from the same top edge with a consistent 28-point corner radius. Reduce Motion disables the transition.

Each opening restores the launcher above the center of the display under the pointer, leaving room for the expanded results. Its top edge stays fixed while typing or clearing a search. Dragging the background does not move the launcher.

By default, whenever Flint opens or regains focus, it switches the system keyboard input source to **ABC** so you can search immediately. Turn off **Switch to ABC** in **Settings → General** to keep your current input method. The setting applies immediately and remembers your choice between launches. ABC must be enabled in macOS Input Sources; if it is unavailable, Flint keeps the current input source.

Settings uses the launcher's arrow-key navigation model. **Up / Down** select settings rows and list items; in Scripts, the arrows continue between the folders and commands lists. **Return** activates the selected row or begins editing a text field. While editing, arrows keep their normal cursor behavior; **Escape** returns to row selection, and Return finishes editing a quick-link field. **Left / Escape** return from content to the sidebar, **Up / Down** select a section there, and **Right / Return** enter that section. Escape from the sidebar closes Settings. The bottom-right action group shows navigation, the selected action, and **Actions** (**Command–K**). The Actions popover uses untinted native Liquid Glass on macOS 26 and later and opens inside the window above the footer with a short fade and slide. Reduce Motion makes the transition immediate. Shortcut keycaps reuse the same keyboard-hint component as the launcher and show press feedback. Up/Down select an action and Return runs it. Escape, Command–K, or clicking outside dismisses it while preserving the selected setting. It provides adding, editing, removing, and other section actions. **Command–1…4** switch directly to General, Quick Links, Scripts, and Translation. **Command–Return** saves a quick link, and Escape from the editor's row selection cancels it. **Tab / Shift–Tab** remain available for moving through individual controls, without requiring macOS Full Keyboard Access. Shortcut recording and input-method composition retain their own keys.

The launcher fades in when shown and fades out when dismissed, including with Escape, the launcher shortcut, and clicking away. Reduce Motion disables these fades.

## Run

Open `Flint.xcodeproj`, select the **Flint** scheme, and run on **My Mac**. Local builds use automatic Apple Development signing with team `Z9W85A679L`, configured in `Config/Base.xcconfig`. A matching signing certificate and private key must be available in your keychain.

Or build and open from the terminal:

```sh
xcodebuild -project Flint.xcodeproj -scheme Flint -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Flint.app
```

To keep the launcher visible when it loses focus, quit Flint first and launch it with `--keep-open`:

```sh
open build/Build/Products/Debug/Flint.app --args --keep-open
```

Escape and your configured launcher shortcut still hide the launcher. Opening an application dismisses Flint immediately, without waiting for the app to finish opening. In Xcode, add `--keep-open` under **Edit Scheme → Run → Arguments Passed On Launch** for the same behavior.

## Repository layout

The Xcode navigator mirrors the folders on disk. `Flint` is the macOS application target; `Sources/FlintCore` and `Tests/FlintCoreTests` keep the standard Swift package layout for testing the core independently.

```text
Flint/
  App/                 Entry point and application lifecycle
  Launcher/            Launcher window, search controller, and rows
  Settings/            Settings shell and keyboard navigation
  Features/            Feature-specific AppKit views and settings
  Shared/              Shared appearance, controls, and result presentation
  Platform/            macOS keyboard integration
  Resources/           Asset catalog
  Supporting/          Info.plist and signing entitlements
Sources/FlintCore/
  Applications/        Application discovery and search
  Launcher/            Feature availability, items, placement, and calculation routing
  Preferences/         Launcher preferences and shortcut models
  Platform/            macOS notification integration
  Features/            One folder per optional feature
Tests/
  FlintCoreTests/      Unit tests grouped by feature and shared responsibility
  FlintAppearanceChecks/  Offscreen integration checks grouped the same way
Config/                Base, Debug, Release, and feature-selection xcconfig files
scripts/               Build and offscreen-check entry points
design/                Branding source artwork and README banner
```

Each optional feature's model and service code lives in `Sources/FlintCore/Features/<Feature>`. Its dedicated AppKit UI, when present, lives in `Flint/Features/<Feature>`, with corresponding tests under `Tests/*/Features/<Feature>`. The folders are `Calculator`, `Timestamps`, `Colors`, `NumberBases`, `QRCode`, `Translation`, `QuickLinks`, `Scripts`, and `SystemActions`.

Calculation routing and the shared calculation result container stay with the launcher and shared UI because they serve several features. Feature folders retain the existing compilation flags and share their current targets. Adding a folder does not create a separate Swift module or exclude its source files from compilation.

Common build and signing settings live in `Config/Base.xcconfig`. `Debug.xcconfig` and `Release.xcconfig` add the configuration-specific compiler settings; both include the same `Features.xcconfig` through the base configuration. The appearance-check script discovers nested Swift sources automatically, excluding the normal app entry point and lifecycle.

## Build-time feature selection

All optional features are enabled by default. Edit `Config/Features.xcconfig` and keep only the flags you want in `FLINT_FEATURES`. This applies to both Debug and Release builds in Xcode. Application discovery, launching, and General settings are always available. An empty `FLINT_FEATURES` builds just those essentials.

For a single build, select features without editing the configuration:

```sh
sh scripts/build.sh --features calculator,colors,qr
sh scripts/build.sh --features none
sh scripts/build.sh --features all -configuration Release
```

Running `sh scripts/build.sh` uses `Config/Features.xcconfig`. The script only builds; open `build/Build/Products/Debug/Flint.app` after quitting any running instance to try a Debug build. Additional arguments are passed to `xcodebuild`.

| Feature name | Folder | Configuration flag |
| --- | --- | --- |
| `calculator` | `Calculator` | `FLINT_CALCULATOR` |
| `timestamps` | `Timestamps` | `FLINT_TIMESTAMPS` |
| `colors` | `Colors` | `FLINT_COLORS` |
| `number-bases` | `NumberBases` | `FLINT_NUMBER_BASES` |
| `qr` | `QRCode` | `FLINT_QR` |
| `translation` | `Translation` | `FLINT_TRANSLATION` |
| `quick-links` | `QuickLinks` | `FLINT_QUICK_LINKS` |
| `scripts` | `Scripts` | `FLINT_SCRIPTS` |
| `system-actions` | `SystemActions` | `FLINT_SYSTEM_ACTIONS` |

Features are selected independently. Disabled tools disappear from launcher search and Settings, and disabled calculation formats stay in normal search. Settings shortcuts become Command–1…N in the order of the remaining sections. Disabling scripts skips script discovery; disabling translation skips the startup Keychain read. Saved preferences, links, script folders, and credentials are retained for future builds.

Selection uses Swift compilation conditions and requires rebuilding to change. Shared model and view types remain compiled, so this is a capability selection mechanism rather than a guarantee of binary-size reduction. Raw `xcodebuild` also accepts a space-separated flag override, such as `FLINT_FEATURES="FLINT_CALCULATOR FLINT_QR"`. Standalone Swift package builds keep all features enabled by default.

Run the offscreen feature integration checks against a selection:

```sh
sh scripts/check-appearance.sh --features none
sh scripts/check-appearance.sh --features calculator,translation
```

These focused checks verify search availability, calculation routing, tool entry, and Settings navigation. Run the full appearance suite without `--features` to check the default all-feature build.

## Applications

Flint discovers installed applications in `/Applications`, `~/Applications`, `/System/Applications`, system CoreServices applications, and the system Cryptex applications folder. It also includes Finder from `/System/Library/CoreServices/Finder.app`. It includes category folders such as Utilities, skips apps embedded inside other apps, and deduplicates applications by bundle identifier. The application list refreshes automatically whenever you reopen the launcher. Discovery runs off the main thread, while native app icons load only for displayed rows.

The launcher opens as a compact search bar. Type to expand the application results; clearing the input collapses it again. Whitespace-only input also keeps it collapsed. Search ignores case and diacritics and supports abbreviations such as `vsc` for Visual Studio Code. Exact names rank before prefixes, substrings, and abbreviation matches. Within each match type, results you use more often in Flint appear higher. Use counts are saved locally between launches. Click an app or press Return to open it. If launching fails, Flint dismisses the launcher and sends a macOS notification with the application name and error details. Application and action errors share the same notification permission.

| Shortcut | Action |
| --- | --- |
| Command–Space | Show or hide Flint |
| Up / Down | Select the previous / next result |
| Return | Open the selected app or run the selected action |
| Tab | Put the selected calculation or conversion result into search, or enter the selected Translate action |
| Escape | Restore the input before Use Result, return from translation to search, or hide Flint |
| Command–R | Refresh installed applications |

Flint also has a flame icon in the menu bar with **Show Flint**, **Settings…**, and **Quit Flint** actions. If another app has reserved the launcher shortcut, use the menu bar to open Flint. Clicking outside the launcher dismisses it.

## Quick Links

Save websites, search URLs, files, folders, and app deeplinks in **Settings → Quick Links**. Use **Add Quick Link…** or search for **Create Quick Link** in Flint and press Return. Give the link a name and destination, then choose **Save Quick Link** (Command–Return). Saved links appear in launcher search alongside applications and actions; click one or press Return to open it.

Destinations accept complete URLs such as `https://github.com`, app deeplinks such as `slack://channel?team=T&id=C`, and absolute paths such as `~/Downloads` or `/Users/you/Projects`. **Open With** optionally chooses an application and shows its icon; the reset icon beside it restores the system default. The editor fits its content and expands to show validation errors. Files and folders use their native icons in launcher search. Missing files or opening failures show an error in Flint.

Add placeholders to make a search or template link, such as `https://google.com/search?q={query}` or `https://github.com/{org}/{repo}`. Flint shows each argument as a query field beside the search text when you select the link. Press **Tab** from search to complete the selected quick link’s full name and focus the first query, then **Tab** to move to the next query (wrapping after the last). **Shift–Tab** moves to the previous query. **Escape** moves one query left; from the first query, it returns to search. The footer shows **Previous query** or **Search** to match. Entered values are kept. Press **Return** or click **Open Quick Link** to open the completed link; an empty required query receives focus instead. When autocomplete changes the name’s width, the query block slides smoothly to its new position while keeping focus and entered values. Reduce Motion makes the move immediate. The accent-colored focus outline switches directly to the active query, with one brief glow pulse on Tab, Escape, or mouse focus in both light and dark appearances. Reduce Motion keeps the outline steady. Long sets of queries scroll horizontally as you navigate. Repeated placeholders share one value; up to eight different arguments are supported. Raycast-style `{argument}` and `{argument name="Query"}` placeholders also work. URL arguments are percent-encoded so spaces, Unicode, and reserved characters stay inside the supplied value. File path arguments preserve spaces. Every argument is required. Query values stay separate from launcher search and clear when you select another link or reopen Flint.

Settings actions use compact icons with borders on hover and tooltips describing each action. Quick Links settings uses the same compact list and integrated toolbar as Scripts. Choose the pencil beside a link to open its editor; hover over a row to see its destination. Use **+** in the list’s footer to create a link, or select a row and choose **−** to remove it. The editor’s action group saves with Command–Return and cancels with Escape. Changes apply to launcher search immediately and persist between launches.

## Script Commands

Run local scripts from launcher search. Open **Settings → Scripts** (or search for **Script Commands**) and choose **Add Folder…**. Flint scans that folder and its subfolders for commands. **Create Script…** saves a working Bash template, adds its folder, and reveals the file in Finder so you can edit it. Removing a folder from Settings keeps its files.

Scripts settings uses the same rounded lists as Translation. **Script Folders** has controls to add a folder, remove the selected folder, or reveal it in Finder. **Commands** shows each script on one row with an **Edit** action that opens its file in TextEdit. Use the refresh button to reload scripts; an **Issues** button appears when a file or folder needs attention. Descriptions and filenames are available in tooltips, without explanatory subtitles.

Commands use [Raycast Script Command metadata](https://github.com/raycast/script-commands), with `@flint` accepted in place of `@raycast`. For example:

```bash
#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Say Hello
# @raycast.mode fullOutput
# @raycast.argument1 {"type":"text","placeholder":"Name"}

printf 'Hello, %s!\n' "$1"
```

Search for the command’s title and press **Return**. Commands without arguments run immediately. Commands with arguments show a form; **Return** or **Run Script** starts execution. Up to three consecutive arguments support `text`, `password`, and `dropdown`, including `optional` and `percentEncoded`. Values are passed as individual process arguments, preserving spaces, quotes, and Unicode. Password fields obscure entry; scripts receive the value as an ordinary process argument.

`fullOutput` shows selectable, scrollable plain text from standard output and errors; `compact` shows the last output line on success; `silent` dismisses Flint after successful completion. Failures show the exit code and available output. **Copy Output** copies captured output. **Cancel** stops a running command; **Back** or **Escape** returns to search after it finishes. Dismissing Flint cancels an active command. Runs stop after 60 seconds, and captured output is limited to 1 MB. Output is shown when execution finishes.

`needsConfirmation true` requires **Confirm & Run**, including for commands without arguments. `description`, `packageName`, and `currentDirectoryPath` are read; the working directory defaults to the script’s folder. Flint invokes the shebang interpreter, so scripts do not need executable permission. The process PATH includes `/opt/homebrew/bin` and `/usr/local/bin`. Install any interpreters your scripts require. Scripts run locally with your Mac user’s permissions.

Supported file extensions are `.sh`, `.bash`, `.zsh`, `.py`, `.rb`, `.js`, `.ts`, `.swift`, `.applescript`, `.scpt` (text), and `.pl`. Hidden files, app packages, and `.template.` files are skipped. Settings lists discovered commands and metadata problems. Use **Refresh**, **Command–R**, or reopen Flint to reload changes. Inline scripts and automatic refresh, ANSI styling, and custom script icons are not supported.

## QR Code Generator

Search for **QR Code Generator** (or **qr**) and press **Tab**, **Return**, or click **Generate QR Code**. Type or paste text or a URL to see a centered QR code instantly. **Return** or **Copy QR Code** copies the high-resolution PNG image and dismisses Flint. The preview and copied image keep a white margin for scanning, including in dark mode.

Generation works entirely offline on this Mac. Text is encoded exactly as entered, including Unicode, spaces, and line breaks, up to **2,000 UTF-8 bytes**. Empty or oversized text disables copying. While the tool is open, calculations and other launcher actions stay out of the way. Press **Escape**, click **Exit**, or press **Backspace** with empty input to return to search. Reopening Flint resets the tool.

## Translation

Find the **Translate** action using normal launcher search, select it, and press **Tab**. Search supports the same prefixes, substrings, and abbreviations as other actions; there is no special trigger word. Return does not enter Translate. Flint clears the search and shows the translation icon and **Text to translate…** placeholder. Type or paste the text to translate: translation starts automatically when you pause typing for **600 ms**. The source language is detected automatically. Press **Return** or click **Copy Translation** when the result is ready to copy it and dismiss Flint. Longer translations scroll and their text can also be selected and copied.

Search input stays on one line and truncates at the end with an ellipsis when it is too long. Pasted line breaks appear as **⏎** symbols in the search bar; the complete original text, including line breaks, is retained for translation. Windows-style CRLF line breaks display one symbol each.

For a standalone word or phrase, a brief **Meaning** section explains its meaning and usage in the target language below the main translation. When the source has several plausible interpretations, **Other meanings** lists their translations and short explanations beneath it. These details scroll with the result and are cached when switching languages. **Copy Translation** copies only the main translation.

Open **Settings → Translation** to save your DeepSeek API key and manage target languages with the list’s **+** and **−** controls. Simplified Chinese is the default; English, Traditional Chinese, Japanese, Korean, French, German, Spanish, Portuguese, Italian, Russian, Arabic, Hindi, Vietnamese, and Thai are also available. The API key is stored in macOS Keychain and shown as dots beside a remove icon after saving. Flint reads the key at startup, before showing the launcher, so any Keychain permission prompt appears before you begin translating. Flint reuses an unlocked key in memory during the app session; saving or removing the key updates that cache.

In translation mode, press **Left / Right** to cycle through your saved target languages, wrapping at either end. Changing the target preserves the input and slides/fades the result in the direction of travel, like color previews. Completed translations for the unchanged input are cached in memory per target: switching back restores the answer and inferred source language immediately. An uncached target translates after the usual pause. Editing the input or leaving translation clears the result cache. The selected language persists between launches. Press **Up** or click **Edit text ↑** to let Left/Right move the cursor instead. Press **Down** or click **Switch language ↓** to resume changing the target. Editing mode stays active while typing; entering translation again restores language switching. Modified arrows and input-method composition keep normal text-editing behavior.

Once the source language is detected, Flint skips it in target cycling and the next-language preview. If it was selected, Flint switches to another saved target automatically. Simplified and Traditional Chinese remain separate translation targets. If the source is your only saved target, Flint temporarily uses Simplified Chinese for English input or English for other input, without changing your saved list. Editing clears the detection so a new source can use all saved targets again.

Before a result is ready, skeleton lines occupy the translation area and blink gently while an API request is in progress. They stay static during the typing pause; Reduce Motion keeps them static and disables switching animations. A dimmed preview on the right shows the next saved target language with its cached translation when available, otherwise skeleton lines, and the same edge fade as color previews. The preview does not send an extra translation request. With one target, the translation uses the full width. Errors and missing-key messages replace the skeleton with actionable text.

After the typing pause, Flint infers the source language locally using macOS Natural Language and displays a preview above the result, such as **English → Simplified Chinese**. The same DeepSeek request returns both the translation and its inferred source-language code as a JSON object. A valid DeepSeek language replaces the local preview; missing or unknown language metadata retains the local result. No second API request is made. The language heading’s tooltip identifies whether the inference came from this Mac or DeepSeek. Uncertain or nonlinguistic input keeps the **Auto-detect** label. Editing or leaving translation clears the previous inference, and input-method composition waits until committed.

Translation uses DeepSeek’s `deepseek-flash` model through its HTTPS Chat Completions API with thinking disabled. Text entered in translation mode is sent automatically after the typing pause, up to 12,000 characters per request. Flint does not save translation history. Every edit restarts the pause, cancels an outstanding request, and clears the previous result; late responses cannot overwrite newer text. Empty input is not sent, and unfinished input-method composition waits until committed. Leaving translation or dismissing the launcher cancels both pending and in-flight requests. Errors explain missing or invalid credentials, insufficient balance, rate limits, connection failures, and incomplete responses, with a retry or Settings action.

Press **Escape**, click **Exit** beside its Escape key hint in the footer action group, or press **Backspace** on an empty translation search bar to return to normal search. The gear button opens Settings; translation results have no separate Settings button. While translation mode is active, the text is treated as translation input even if it looks like a calculation, color, app, or action. Opening Flint again starts in normal search.

API reference: [DeepSeek Chat Completions](https://api-docs.deepseek.com/api/create-chat-completion/).

## Calculator

Press **Tab** or click **Use Result** in the action group on an arithmetic, timestamp, number-base, or color result to replace the search input with its selected output. Flint stays open with the cursor at the end so you can continue typing. Tab uses the same value as copying, including the selected rounding precision, timestamp unit, number base, or color format, without numeric grouping separators or the continuation marker. The new input is evaluated normally, and the clipboard is unchanged.

Press **Escape** or click **Back** in the action group to restore the input from before **Use Result**, including its precision, output format, and editing mode. Each Escape steps back through one result substitution, even after further typing. When no earlier input remains, Escape dismisses Flint. Reopening Flint or entering translation clears this history; using a result identical to the input adds no history entry.

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

## Number Base Conversion

Type a hexadecimal (`0xff`), binary (`0b101010`), or explicitly marked decimal (`0d255`) integer into search to see **DEC**, **HEX**, and **BIN** equivalents. Prefixes and hex digits ignore case. Bare integers keep their Unix timestamp behavior, and `#` colors keep their color conversion behavior.

Press **Left / Right** to cycle through the selected output, wrapping at either end. Hex and binary input initially select decimal output; decimal input initially selects hex. A format you select stays selected while using the launcher; reopening restores the defaults. The selected row is emphasized, and the footer names each arrow's destination. Press **Return** or click **Copy Number** to copy the selected value and dismiss Flint. Decimal output has no prefix; hex uses `0x` and uppercase digits, and binary uses `0b`. Binary digits are grouped in fours for display; copying removes the spaces. Long values use smaller monospaced text so every digit stays visible.

Press **Up** or click **Edit number ↑** to use Left/Right for cursor movement. Press **Down** or click **Switch base ↓** to resume output switching. Editing mode and the selected output survive incomplete input. Modified arrows retain normal text editing behavior. Reopening Flint restores output switching.

Conversion runs offline with exact integer arithmetic. Magnitudes range from 0 through 18,446,744,073,709,551,615 (64 bits). An optional leading `-` applies the same range to negative magnitudes, and negatives retain a minus sign in every base; negative zero becomes zero. An optional leading `+` is also accepted. Invalid digits, incomplete prefixes, fractions, arithmetic, digit separators, and overflowing values stay in normal search.

## Color Conversion

Type a color into search to preview it and copy it in another format. Flint recognizes 3, 4, 6, and 8 digit hex colors (`#f63`, `#ff636380`); `rgb()` and `rgba()` with commas or spaces (`rgb(255, 99, 99)`, `rgb(255 99 99 / 50%)`); `hsl()` and `hsla()`; and `hwb()`, `lab()`, `lch()`, `oklab()`, and `oklch()`.

A compact swatch previews the color over a checkerboard so transparency stays visible. The selected output appears beside it, followed by dimmer upcoming formats in a horizontal strip that fades at the right edge. Press **Left Arrow** or **Right Arrow** to cycle through **HEX → RGB → HSL → HWB → LAB → LCH → OKLAB → OKLCH**, wrapping at either end. The output strip slides between formats and fades the selected format into focus; Reduce Motion disables this animation. Press **Return** or click **Copy Color** to copy the displayed value and dismiss Flint. The footer labels each arrow with its destination format: when RGB is selected, it shows **HEX ←** and **HSL →**. Press **Up Arrow** or click **Edit color ↑** to move the cursor with Left/Right. Press **Down Arrow** or click **Switch format ↓** to resume format switching. Entering editing mode keeps the selected output format and copy value; editing mode also survives incomplete color input. Reopening Flint enables format switching again. Modified arrows still edit the search text. Hex input starts with RGB output; other inputs start with HEX. A format you select stays selected while you use the launcher; reopening resets the default.

Alpha is included in every output when the color is transparent. Hex rounds each channel to 8 bits. Lab and OKLab conversions retain colors outside sRGB; the preview and HEX/RGB/HSL/HWB outputs clip to sRGB and show a hint when clipping occurs. Invalid or incomplete colors stay in normal search. Conversions run offline.

## Actions

Search for **Eject All Disks**, **Empty Trash**, or **Show Desktop**, then click the result or press Return. Actions appear alongside applications with an **Action** label and a **Run Action** button.

**Eject All Disks** safely ejects removable or ejectable volumes, including external disks and disk images, and excludes internal, hidden, and non-browsable volumes such as iOS Simulator runtimes. It attempts every eligible disk and reports any failures, such as a disk being in use. **Empty Trash** asks for confirmation before permanently deleting items through Finder; macOS may request permission for Flint to control Finder. An already empty Trash succeeds without requesting deletion. After confirmation, Flint temporarily suppresses Finder’s separate emptying warning, restores your warning preference even if deletion fails, and checks that the Trash is empty. Finder failures remain visible. **Show Desktop** uses Mission Control’s desktop mode without depending on your keyboard shortcut. Actions dismiss Flint before running. Failures send a macOS notification with the action name and error details instead of reopening the launcher. Flint requests notification permission on the first failure; notifications follow your settings in System Settings → Notifications → Flint.

Dialogs use untinted regular Liquid Glass on macOS 26 and later, with a standard popover material on older versions, and dim only the inside of the rounded launcher. Native macOS push buttons show Escape and Return key hints: Escape cancels and Return confirms (or acknowledges an error). Keyboard hints use consistent rounded rectangle outlines and symbols in the launcher footer, dialogs, and Settings launcher shortcut control. Labeled hints keep a consistent gap between the action text and the outlined key. Each key runs its labeled action directly; dialog buttons have no selection or navigation state. Closing a dialog returns focus to search. Action icons are smaller than application icons while keeping the result text aligned.

The **action group** is the pill in the footer's bottom-right corner. Its width animates as action titles, precision controls, or timestamp unit hints change, keeping its right edge fixed. Reduce Motion disables this animation.

## Settings

Settings uses a resizable sidebar layout with a compact **General** card for **Open at Login**, **Show in Menu Bar**, **Switch to ABC**, and **Launcher Shortcut**. The launcher shortcut uses the shared keyboard component to show each key as an outlined keycap, with a reset button beside it. Settings follows the system’s light or dark appearance.

Turn on **Open at Login** in General to start Flint automatically when you log in. Login launches keep the launcher hidden until you use the shortcut or menu. The switch reflects macOS’s login-item status; if approval is required, use **Open Login Items…** to allow Flint in System Settings. Turn the switch off to remove the login item. **Show in Menu Bar** controls the flame icon and remembers your choice between launches. When hidden, you can still open Flint with its shortcut or by launching the app, and open Settings with Command–Comma.

Open Settings with **Command–Comma**, the gear button in the launcher footer, or **Settings…** in the flame menu. Click the shortcut button and press your own key combination. Use Command, Option, or Control with a key (and optionally Shift), or a function key such as F6. Escape cancels recording, and Tab leaves the recorder. Recording also cancels if Settings loses focus or closes. The active launcher hotkey is temporarily suspended during recording so you can record the same combination again.

Close Settings with **Command–W** or the red close button. Flint keeps running so you can open the launcher again.

Changes apply immediately, update the menu shortcut, and persist between launches. Previously saved shortcuts carry over. The reset button beside the shortcut returns to Command–Space. A registration failure is shown in Settings and keeps the previous preference selected.

The `--keep-open` argument is a testing option only; it is not shown or saved in Settings.

## Checks

The core logic is also a standalone Swift package:

```sh
swift test
sh scripts/check-appearance.sh
cognitive --threshold 15 Sources Flint Tests
```

Desktop appearance checks run offscreen and do not activate their windows or take keyboard focus. Image previews can be rendered to files while the windows stay offscreen.

This version contains application search and launching, quick links, DeepSeek translation, numeric calculations, number base and color conversion, system actions, and shortcut settings.

## License

Flint's original work is licensed under the [MIT License](LICENSE).
See [third-party notices](THIRD_PARTY_NOTICES.md) for material covered by other terms.
