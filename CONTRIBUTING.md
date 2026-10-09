# Contributing to Brushwood

Thanks for helping! Bug reports, translation fixes, feature requests and pull requests are all welcome.

## Ground rules

- **Brushwood works like Paint.NET.** When Brushwood and Paint.NET behave differently, Paint.NET is usually right. Known,
  deliberate differences are listed under [Known differences from Paint.NET](README.md#known-differences-from-paintnet).
  When you report a difference or change a behavior, describe what Paint.NET does.
- **No Paint.NET code or assets.** Do not copy code, icons or other resources from Paint.NET, and do not decompile it.
  Reimplement behavior from what Paint.NET does, its documentation or published algorithms, and say in your pull request
  where an algorithm comes from.
- **No third-party dependencies.** Brushwood builds with the Xcode Command Line Tools alone. If you think a dependency is
  needed, open an issue first.

## Reporting a bug or asking for a feature

Use the [issue forms](https://github.com/balaborde/brushwood/issues/new/choose). For a bug, the most useful things are
the steps to reproduce it, your Brushwood and macOS versions, and if possible the image file. GitHub only accepts some
file types, so zip a `.pdn` or `.ora` file before attaching it.

If macOS refuses to open Brushwood the first time, that is expected: see [Installing](README.md#installing).

## Translations

Brushwood's interface is available in 12 languages. Most translations have not been reviewed by native speakers yet,
so corrections are very welcome, even for a single word. You can report them with the translation form, or fix them
yourself:

1. Each language has a table in `scripts/translations/<code>.py`, with one `English source text|translation` per line.
   Edit the right-hand side only.
2. Run `python3 scripts/gen_strings.py`. It regenerates `Resources/<code>.lproj/Localizable.strings` and rejects
   translations whose `%@` / `%d` placeholders differ from the English text.
3. Build and open Brushwood in your language, for example German:

   ```sh
   scripts/build-app.sh
   build/Brushwood.app/Contents/MacOS/Brushwood -AppleLanguages "(de)"
   ```

4. Check that your text fits. This lists the controls that are too narrow for their text, in every tool bar and window:

   ```sh
   BRUSHWOOD_SNAPSHOT="$(mktemp -d)/fit" BRUSHWOOD_SCRIPT=fitreport build/Brushwood.app/Contents/MacOS/Brushwood -AppleLanguages "(de)"
   ```

   Lines starting with `TRUNC` or `OVERFLOW` point to text that is cut off: shorten it. `WRAPS` only means the tool bar
   uses a second row, which is fine.

Commit both the table and the regenerated `.strings` file. To add a new language, follow the steps under
[Localization](README.md#localization).

## Working on the code

You need macOS 13 or later and Swift 5.9 or later; the Xcode Command Line Tools are enough. [Building](README.md#building)
and [Project layout](README.md#project-layout) in the README show how to build and where things are. During development,
`swift run Brushwood` is the quickest way to try a change.

- Write code that reads like the code around it: same naming, same structure, comments only where the reason is not
  obvious.
- Interface text is written in English with `L("…")`, or `LF("…", args)` for formatted text. After adding or changing
  text, run `python3 scripts/gen_strings.py`. New text shows in English until it is translated; translating it is welcome
  but not required.
- If your change is visible in the README screenshots, you can regenerate them with `scripts/make-readme-images.sh`
  (see [README pictures](README.md#readme-pictures)), or leave it to the maintainer.

### Tests

Run these before opening a pull request:

```sh
swift run -c release selftest   # engine tests
scripts/ui-smoke-test.sh        # drives the app through scripted scenarios
```

`scripts/screen-check.sh` also checks what really appears on screen; it needs Screen Recording permission for your
terminal.

When you fix a bug, add a test that fails without your fix:

- **Engine** (pixels, layers, selections, effects, file formats): add a `run("…") { expect(…) }` block in
  `Tests/SelfTest/main.swift`.
- **App** (tools, menus, windows): add a scenario to `scripts/ui-smoke-test.sh`. Scenarios are written with the commands
  of `Sources/Brushwood/App/DebugScript.swift`, such as `tool:paintbrush; drag:10,10,50,50; expect:30,30,FF0000`.

## Pull requests

- Keep each pull request to one topic, branched from `main`.
- Explain what changes for the user and, for behavior changes, what Paint.NET does.
- Add before/after screenshots for visible changes.
- Make sure the tests pass.

By contributing, you agree that your work is released under the [MIT License](LICENSE), like the rest of Brushwood.
