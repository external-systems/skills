# Under the hood: pkgs flakeModules.docs

Read this when debugging a build or changing the module. Source:
`flakeModules/docs.nix`, `flakeModules/docs/inline-markdown.py` and
`flakeModules/docs/org/` in external-systems/pkgs;
`flake-parts/flakeModules.nix` exports it.

## Binding

`flakeModules.nix` exports `flake-parts-lib.importApply
../flakeModules/docs.nix {orgInputs = inputs;}`: the module sees pkgs'
own `reveal-js` input, so consumers declare none. Each exported module
has a `key`, so importing `flakeModules.docs` next to
`flakeModules.default` (which imports it) does not declare options twice.
pkgs' own dev partition imports the files by path with the same
`orgInputs` (reading `self.flakeModules` there would recurse).

## Third-party files, no npm

| File | From | When fetched |
| --- | --- | --- |
| reveal.js `dist/` | pkgs input `reveal-js` (a release tag, which commits the prebuilt `dist/`, `flake = false`) | any deck |
| `rough.js` 4.6.6 | `fetchurl` of the npm registry tarball, `postFetch` keeps `package/bundled/rough.js` | `slides.sketch.enable` |
| `mermaid.min.js` 11.17.2 | `fetchurl` of the npm registry tarball (~18 MB), `postFetch` keeps `package/dist/mermaid.min.js` (3.5 MB) | `mermaid.enable` (a page uses Mermaid) |

The hash pins the extracted file, so the store keeps only that file and
no lock node is added. Mermaid stays on major 11, which Material 9.x
expects; Material uses a global `mermaid` when one is loaded and only
falls back to unpkg.com otherwise. Upgrade: change the version and URL,
build once with `lib.fakeHash`, take the hash from the error.

## MkDocs

`pkgs.python3.withPackages` with mkdocs, mkdocs-material,
mkdocs-glightbox, pymdown-extensions and `docs.extraPythonPackages`,
from the consumer's nixpkgs (= the org nixpkgs), so it substitutes from
cache.nixos.org.

The config: `docs.settings`, plus `theme.custom_dir` (a store dir with
`stylesheets/org.css` and, with Mermaid, `javascripts/mermaid.min.js`;
Material copies theme files into the site, for the build and the live
preview alike), `extra_css` and `extra_javascript` prepended. It is
written as JSON (`mkdocs.json`), then `sed` un-quotes every
`"!!python/name:x"` string into the YAML tag `!!python/name:x ` (JSON is
YAML; the space after the tag is required).

`packages.documentation` is one `runCommand`: copy `docs.root` (via
`builtins.path`, so only that subtree is an input), write the generated
`mkdocs.yml` unless the repo has one, copy the built deck to
`docs/slides`, `mkdocs build --strict --site-dir $out`.

`apps.watch-documentation` runs from the git top level. With a repo
`mkdocs.yml` it serves that; otherwise jq sets `docs_dir` to the
checkout's absolute `docs/` in the JSON, then the same `sed`, so edits
reload.

`docs.mermaid.enable` defaults to whether any `.md` under `docs/`
contains ` ```mermaid ` (`lib.filesystem.listFilesRecursive` +
`readFile` at eval time), so a site without diagrams never downloads
Mermaid.

## Slides

`packages.slides`: copy `slides.dir`; add the generated `index.html`
unless the deck has one; run `inline-markdown.py` (every `<section
data-markdown="x.md"></section>` gets the Markdown folded into a
`<textarea data-template>` and the `.md` is deleted, so the deck opens
from `file://` and MkDocs never sees a stray `.md`); copy reveal.js
`dist/` to `reveal/` and the org files to `org/`.

The generated page loads, in order: reveal.js reset, core, the base
theme, monokai, `org/org.css` (org style), `extraHead`; then reveal.js,
the Markdown, Highlight and Notes plugins, `org/speaker-sync.js`,
`org/rough.js` + `org/sketch.js`, `extraBody`; then
`Reveal.initialize(config).then(sketchDiagrams)`.

`org/` holds only what is enabled: `org.css` (orgStyle),
`speaker-sync.js` (speakerSync), `rough.js` and `sketch.js` (sketch).

`apps.serve-slides`: symlinks the checkout's deck files, `reveal/`,
`org/` and the generated `index.html` (if the deck has none) into a temp
dir and serves it with `python3 -m http.server`, live from the checkout.

## Speaker sync

reveal.js' speaker view moves its own preview first and tells the main
window afterwards, with a delay, so fast clicking makes the audience
screen lag, skip steps and jump back. `speaker-sync.js` runs inside the
speaker view's preview (it detects the `receiver` and
`postMessageEvents` query) and sends every key press straight to the
main window's `Reveal.triggerKey`; the preview then follows the main
window. Elsewhere it does nothing.

