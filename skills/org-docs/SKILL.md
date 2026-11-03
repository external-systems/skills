---
name: org-docs
description: "The docs site and slide deck every external-systems repo has, and the org style they share: external-systems/pkgs flakeModules.docs builds a MkDocs (Material) site and a reveal.js deck from plain Markdown with zero npm, in the org look (clay on warm dark and cream), with Mermaid, emoji, speaker-view sync and hand-drawn sketch diagrams. Covers the layout, the docs.* options, writing slides and the org building blocks, overrides, previews, Pages, how the module works, and migrating a repo. Load whenever the user mentions docs, MkDocs, reveal.js, slides, a deck, a presentation, diagrams, GitHub Pages or the org style in a Nix/flake repo, or the retired external-systems/presenting flake."
---

# org-docs — docs and slides in every org repo

Every org repo has a website and a slide deck, built by Nix from plain
Markdown with zero npm: a MkDocs (Material) site with the deck embedded
at `/slides/`. All build logic and the org style live in
external-systems/pkgs `flakeModules.docs` (part of `flakeModules.dev`,
which every repo imports: the `org-standards` skill). A repo writes
Markdown and at most a few `docs.*` settings.

external-systems/presenting, its `presenting.slides.*` and
`documentation.*` options, and mkdocs-flake are retired: see
[Migrating a repo](#migrating-a-repo).

## Layout, by convention

```
documentation/
  docs/index.md        the site, one Markdown file per page
  slides/slides.md     the deck
  slides/custom.css    optional: this deck's own CSS (extraHead)
  slides/icons/ ...    optional: images the deck uses
flake-parts/docs.nix   optional: docs.* settings that differ
```

No `mkdocs.yml`, no deck `index.html`: both are generated. **`git add`
every new file**; Nix only sees tracked files, and the error never
mentions git.

| Command | Result |
| --- | --- |
| `nix build .#documentation` (`docs-build`) | the site, deck at `slides/`; open `result/index.html` from disk |
| `nix build .#slides` | the deck alone, opens from `file://` |
| `nix run .#watch-documentation` (`docs`) | live site, 127.0.0.1:8981 |
| `nix run .#serve-slides` (`slides`) | live deck, 127.0.0.1:8982 (press S for speaker view) |
| `devenv up` | both previews |
| `nix flake check` | builds both (`checks.documentation`, `checks.slides`) |

Publishing: merge to `main`; the org CI deploys the site to GitHub Pages
at `https://<repo>.external.systems/`. Never commit build output.

## The org style

On by default (`docs.orgStyle.enable`), for site and deck alike. It is
the look first built in external-systems/explain-kube-to-me:

- **Palette:** clay-orange accent (`#d97757`, soft `#e8a48a`) on warm
  dark (`#1f1e1d`, deep `#141413`, surfaces `#2b2a27`/`#363430`) and
  cream (`#faf9f5`), muted text `#b0aea5`; supporting blue `#6a9bcc`,
  green `#8fa876`, sand `#e3c08d`, rose `#c9789a`. The deck exposes them
  as CSS variables (`var(--clay)`, `--cream`, `--muted`, `--surface`,
  ...), so a deck's own CSS uses the same colours.
- **Type:** Georgia serif headings, larger body text; slide titles get a
  short clay underline; `**bold**` is clay, `*em*` is sand.
- **Site:** Material light and dark modes in the palette, system fonts
  (no Google Fonts request), Mermaid diagrams and emoji, offline search;
  the build browses from disk.
- **Deck:** 1280×720, slide transition, fading backgrounds, progress
  bar, `h.v` slide numbers, auto-animate; speaker-view sync; hand-drawn
  sketch diagrams; the shared building blocks.

Writing slides, the building blocks and sketch diagrams:
[references/org-style.md](references/org-style.md). Start a deck from
[references/starter-deck/slides.md](references/starter-deck/slides.md).

## Settings

Everything is optional; set only what differs, in any flake-parts module
(`flake-parts/docs.nix` by convention):

```nix
{
  perSystem.docs = {
    repo = "home"; # site_url https://home.external.systems/, repo + edit links
    settings = {   # mkdocs.yml as Nix, merged over the org defaults
      site_name = "external-systems home";
      nav = [
        {Home = "index.md";}
        {Fleet = ["fleet/index.md" "fleet/remote-builder.md"];}
      ];
      plugins = ["search" "offline" "glightbox" "tags"];
    };
    extraPythonPackages = ps: [ps.mkdocs-redirects];
    slides = {
      title = "Home fleet";
      config.transition = "fade"; # Reveal.initialize, over the org defaults
      # The deck's own files, loaded after the org style:
      extraHead = ''<link rel="stylesheet" href="custom.css" />'';
      extraBody = ''<script src="deck.js"></script>''; # needs Reveal
    };
  };
}
```

All options and defaults: [references/options.md](references/options.md).
Without `nav`, MkDocs builds the navigation from the files. A list
setting (`plugins`, `markdown_extensions`, `theme.features`, `palette`)
replaces the default list, so repeat the entries you keep. A setting
that needs a Python object is the string `"!!python/name:module.attr"`;
the generated `mkdocs.yml` writes it as that YAML tag.

## Overrides, best first

1. **The defaults.** Most repos set `repo`, `site_name` and `nav`.
2. **`docs.*` options** for anything settings-shaped.
3. **The deck's own files** in `documentation/slides/` (CSS, images,
   scripts), copied with the deck and loaded with `extraHead` /
   `extraBody`. Only what is specific to this deck; build on the org
   variables and blocks.
4. **A pkgs PR** for anything every repo would want: it becomes an
   option or a default for all of them (that is how the org style got
   there).
5. **Last resort, whole files:** `documentation/mkdocs.yml` replaces the
   generated config (`docs.settings` and the org site CSS are then
   ignored); `documentation/slides/index.html` replaces the generated
   deck page (the org files are still at `org/` for it to load).

## Linking the deck from a page

Plain HTML, never a Markdown link: strict builds check Markdown links
against `docs/`, where `slides/` exists only mid-build.

```html
<iframe src="slides/index.html" title="Slide deck"
  style="width: 100%; aspect-ratio: 16 / 9; border: 0;"
  allowfullscreen></iframe>
```

URLs are relative to the page (`use_directory_urls: false`): from
`docs/index.md` it is `slides/index.html`, from `docs/a/page.md`
`../slides/index.html`.

## Migrating a repo

From presenting, a dev partition or a hand-written config:

1. `nix flake update org-pkgs`; import `inputs.org-pkgs.flakeModules.dev`
   in `flake.nix`; drop the partition and `dev/` (the `org-standards`
   skill's converge procedure).
2. Port `mkdocs.yml` into `docs.settings` in `flake-parts/docs.nix` and
   delete it. Drop what the org defaults already give (palette, Mermaid
   and emoji extensions, offline, features); `!!python/name:` values
   become strings.
3. Delete a deck `index.html`, `speaker-sync.js`, `sketch.js` and any
   vendored rough.js: the org style has them. Trim the deck's CSS to what
   is its own and load it with `extraHead`; move `Reveal.initialize`
   options to `docs.slides.config`.
4. Fix deck links for `use_directory_urls: false` (`../slides/` from a
   top-level page becomes `slides/`).
5. `sync-locks`, `fmt`, `check`, `nix build .#documentation .#slides`;
   open both and compare with the old build.

While a repo still imports presenting, `docs.enable` and
`docs.slides.enable` stay off, so bumping org-pkgs alone never breaks it.

## Never

- Commit build output (`result*`, `_site/`, `site/`,
  `documentation/site/`, HTML built from `slides.md`) or push `gh-pages`.
- Copy the module, `inline-markdown.py`, a reveal.js, rough.js or
  Mermaid copy, or a MkDocs Python env into a repo; add presenting or
  mkdocs-flake as an input. A missing feature is a pkgs PR
  (`flakeModules/docs.nix`).
- Load anything from a CDN in a deck or page: everything ships with the
  build, so it works offline and from `file://`.

How the module builds all this: [references/under-the-hood.md](references/under-the-hood.md).
