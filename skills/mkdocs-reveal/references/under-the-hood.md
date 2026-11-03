# Under the hood: pkgs flakeModules.docs

Read this when debugging a build or changing the module. Source:
`flakeModules/docs.nix` (+ `flakeModules/docs/inline-markdown.py`) in
external-systems/pkgs; `flake-parts/flakeModules.nix` exports it.

## Binding

`flakeModules.nix` exports `flake-parts-lib.importApply
../flakeModules/docs.nix {orgInputs = inputs;}`: the module sees pkgs'
own `reveal-js` input, so consumers declare none. Each exported module
has a `key`, so importing `flakeModules.docs` next to
`flakeModules.dev` (which imports it) does not declare options twice.
pkgs' own dev partition imports the files by path with the same
`orgInputs` (reading `self.flakeModules` there would recurse).

## MkDocs

`pkgs.python3.withPackages` with mkdocs, mkdocs-material,
mkdocs-glightbox, pymdown-extensions and `docs.extraPythonPackages`,
from the consumer's nixpkgs (= the org nixpkgs), so it substitutes from
cache.nixos.org. No mkdocs-flake.

`packages.documentation` is one `runCommand`: copy `docs.root` (via
`builtins.path`, so only that subtree is an input), write the generated
config as `mkdocs.yml` unless the repo has one (`builtins.toJSON
docs.settings`: JSON is YAML), copy the built deck to `docs/slides`,
`mkdocs build --strict --site-dir $out`.

`apps.watch-documentation` runs from the git top level. With a repo
`mkdocs.yml` it serves that; otherwise it writes the generated config to
a temp dir with `docs_dir` set to the checkout's absolute `docs/` (jq),
so edits reload.

## Slides

reveal.js release tags commit the prebuilt `dist/`; pkgs pins one as a
`flake = false` input and copies `dist/` next to the deck as `reveal/`.
No npm. Upgrade: bump the tag in pkgs' `flake.nix`, `nix flake update
reveal-js`.

`packages.slides`: copy `slides.dir`, add the generated `index.html`
unless the deck has one, run `inline-markdown.py` (every `<section
data-markdown="x.md"></section>` gets the Markdown folded into a
`<textarea data-template>`, the `.md` is deleted: the deck opens from
`file://` and MkDocs never sees a stray `.md`), copy `reveal/`.

`apps.serve-slides`: symlinks the checkout's deck files, `reveal/` and
the generated `index.html` (if the deck has none) into a temp dir and
serves it with `python3 -m http.server`, live from the checkout.

## Transition guard

`docs.enable` and `docs.slides.enable` default to false when perSystem
has `options.documentation` (mkdocs-flake) or `options.presenting`, so a
repo still on presenting can bump org-pkgs without two modules defining
`packages.documentation`. Remove the guard once no repo imports
presenting.
