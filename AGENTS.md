# Development workflow

After making changes to Flint, build the app and run the relevant checks.

Always run tests and appearance checks offscreen. Keep test windows away from the user’s displays and do not activate them or take keyboard focus. Render preview images offscreen for visual inspection. Do not use `FLINT_UI_TESTS_VISIBLE=1`.

Restart Flint as the last step, after all edits, checks, visual inspection, and cleanup are complete. Quit the running instance, then launch the latest build normally so the user can review it:

```sh
open build/Build/Products/Debug/Flint.app
```

The final launch must omit `--keep-open` so Flint dismisses normally when it loses focus. Do not run further tests or make further edits after this restart; if more changes are needed, repeat the checks and restart again as the final step.
