---
name: mkdocs-reveal
description: "Add or change a MkDocs documentation site and a reveal.js slide deck in a Nix flake repo (packages.documentation, packages.slides, live-preview apps, GitHub Pages deploy) with external-systems/pkgs flakeModules.docs, which carries MkDocs from nixpkgs, the reveal.js pin and all build logic, so a repo writes Markdown and at most a few docs.* settings. Load this whenever the user mentions MkDocs, reveal.js, slides, slide decks, presentations, docs sites, or GitHub Pages in a Nix/flake context, wants markdown turned into a website or deck, asks to document a flake repo, or mentions the old external-systems/presenting flake."
---

# MkDocs + reveal.js in a flake

Two build artifacts from plain Markdown, built by Nix with zero npm: a
MkDocs (Material) website and a reveal.js deck, embedded in the site at
`/slides/`. All build logic lives in external-systems/pkgs as
`flakeModules.docs` (also part of `flakeModules.dev`). A repo never copies
build code and declares no docs input: MkDocs comes from the org nixpkgs,
reveal.js from pkgs' own `reveal-js` input.

external-systems/presenting is retired. Its `flakeModules.default`,
`flakeModules.slides` and `lib.mkSlides`, the `documentation.*` and
`presenting.slides.*` options, and mkdocs-flake are the old pattern. To
move a repo off them, see [Migrating off presenting](#migrating-off-presenting).

## Pick the path

- **New repo** → `nix flake init -t github:external-systems/pkgs`; docs
  and slides are already wired (the `nix-style` skill's new-repo
  procedure).
- **Existing org repo** → import `inputs.org-pkgs.flakeModules.dev` in
  `flake.nix` (the rest of this file).
- **A flake outside the org, without the rest of the standard** → import
  `inputs.org-pkgs.flakeModules.docs` alone.
- **Debugging the build or changing the module** →
  `references/under-the-hood.md`.

## Wire it

```nix
# flake.nix
{
  inputs = {
    org-pkgs.url = "github:external-systems/pkgs";
    nixpkgs.follows = "org-pkgs/nixpkgs";
    flake-parts.follows = "org-pkgs/flake-parts";
    import-tree.follows = "org-pkgs/import-tree";
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux" "aarch64-linux"];
      imports = [
        inputs.org-pkgs.flakeModules.dev # treefmt, docs + slides, lock-sync
        (inputs.import-tree ./flake-parts)
      ];
    };
}
```

Then write Markdown. By convention, with no Nix:

```
documentation/
  docs/index.md        the site, one file per page
  slides/slides.md     the deck (optional)
```

**`git add` every new file.** Nix evaluates the git tree; untracked files
don't exist, and the error never mentions git.

| Command | Result |
| --- | --- |
| `nix build .#documentation` | the site, deck at `slides/`; open `result/index.html` from disk |
| `nix build .#slides` | the deck alone (opens from `file://`) |
| `nix run .#watch-documentation [-- PORT]` | live docs, `127.0.0.1:8981` (devenv `docs`) |
| `nix run .#serve-slides [-- PORT]` | live deck, `127.0.0.1:8982` (devenv `slides`) |
| `devenv up` | both previews |

`flakeModules.dev` also adds `checks.documentation` and `checks.slides`,
so `nix flake check` (and CI) fails on a broken docs build.

## Settings

Everything is optional; set only what differs, in any flake-parts module
(the template uses `flake-parts/docs.nix`):

```nix
{
  perSystem.docs = {
    repo = "home"; # site_url https://home.external.systems/, repo + edit links
    settings = {   # mkdocs.yml as Nix, merged over the org defaults
      site_name = "external-systems home";
      nav = [{Home = "index.md";} {Fleet = "fleet/index.md";}];
      plugins = ["search" "offline" "glightbox" "tags"];
    };
    extraPythonPackages = ps: [ps.mkdocs-redirects]; # more plugins
    slides = {
      title = "Home fleet";
      theme = "white"; # reveal.js theme
      config = {transition = "fade"; width = 1280; height = 720;};
      extraHead = ''<link rel="stylesheet" href="custom.css" />'';
    };
  };
}
```

All options with defaults: `references/options.md`. The org defaults are
Material (light/dark palette, system fonts), `search` + `offline`,
`use_directory_urls: false` (the site browses from `file://`), and the
common pymdownx extensions. Without `nav`, MkDocs builds the navigation
from the files. A list setting (`plugins`, `markdown_extensions`,
`theme.features`) replaces the default list, so repeat the defaults you
keep.

Escape hatches, used as-is when present:

- `documentation/mkdocs.yml` replaces the generated config
  (`docs.settings` is then ignored). Needed only for what JSON cannot
  express, such as `!!python/name:` tags.
- `documentation/slides/index.html` replaces the generated deck page.

## The deck

`slides.md` separators, matched against whole lines: `---` next slide,
`--` slide below, `Note:` speaker notes to the end of the slide. Start
from `references/starter-deck/slides.md`. Images, CSS and JS go next to
it in `slides/` and are copied with the deck; load extra CSS/JS with
`docs.slides.extraHead`.

## Linking the deck from a page

Plain HTML, never a Markdown link: strict builds check Markdown links
against `docs/`, where `slides/` exists only mid-build.

```html
<iframe src="slides/index.html" title="Slide deck"
  style="width: 100%; aspect-ratio: 16 / 9; border: 0;"
  allowfullscreen></iframe>
```

The URL is relative to the page (`use_directory_urls: false`): from
`docs/index.md` it is `slides/index.html`, from `docs/a/page.md` it is
`../slides/index.html`.

## Migrating off presenting

1. `nix flake update org-pkgs` (pkgs with `flakeModules.docs`).
2. `flake.nix`: import `inputs.org-pkgs.flakeModules.dev` at the root;
   remove `partitionedAttrs`, `partitions.dev` and the
   `flakeModules.partitions` import (unless the repo keeps a real
   dev-only input).
3. `git rm -r dev/` (`flake.nix`, `flake.lock`, `flake-module.nix`); move
   any repo checks or apps from `dev/flake-module.nix` into
   `flake-parts/`.
4. Replace `documentation/flake-module.nix` with `docs.*` settings in
   `flake-parts/docs.nix`, or delete it. Port `mkdocs.yml` into
   `docs.settings` and delete it (keep it only as the escape hatch); delete
   `slides/index.html` unless the deck needs its own.
5. `sync-locks`, `fmt`, `check`, `nix build .#documentation`; open the
   result and compare with the old site.

While a repo still imports presenting's module, `docs.enable` and
`docs.slides.enable` stay off, so step 1 alone never breaks a build.

## What not to do

- **Never commit build output**: no `result`/`result-*`, `_site/`,
  `site/`, `documentation/site/` (all gitignored), no built deck or HTML
  from `slides.md`, no `gh-pages` pushes. CI (the org CI's `deploy` job)
  is the only publisher; merge to `main` to publish.
- Never copy the module, `inline-markdown.py`, a reveal.js pin or a
  mkdocs Python env into a repo. Never add mkdocs-flake or presenting as
  an input. A missing feature is a pkgs PR (`flakeModules/docs.nix`).
