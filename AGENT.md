# Development workflow

After making changes to Flint, build the app, run the relevant checks, and restart it with the latest build so the user can review the changes.

Keep desktop appearance checks offscreen (the default) so they do not interrupt the user. Use `FLINT_UI_TESTS_VISIBLE=1` only when visible inspection is requested. Preview images can be rendered offscreen.

Use `--keep-open` when launching Flint for testing so it stays visible when focus moves to testing tools. Quit the running instance first, then launch the latest build with:

```sh
open build/Build/Products/Debug/Flint.app --args --keep-open
```

When testing is complete, quit the testing instance and restart the latest build without `--keep-open` before handing it back to the user. The final restart must restore normal dismissal when Flint loses focus:

```sh
open build/Build/Products/Debug/Flint.app
```
