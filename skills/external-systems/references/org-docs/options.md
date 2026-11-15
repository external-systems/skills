# docs.* options (pkgs flakeModules.docs)

All under `perSystem.docs`. Source of truth: `flakeModules/docs.nix` in
external-systems/pkgs, and its docs page "Docs and slides".

| Option | Default | Meaning |
| --- | --- | --- |
| `enable` | `documentation/docs/` exists | site + `apps.watch-documentation` |
| `root` | `"${self}/documentation"` | documentation directory |
| `path` | `root` relative to the repo | where the live preview serves from |
| `repo` | `null` | org repo name: `site_url`, `repo_url`, `repo_name`, `edit_uri` |
| `settings` | org defaults | mkdocs.yml as Nix (freeform), merged over `mkDefault` defaults; `"!!python/name:x"` strings become YAML tags |
| `orgStyle.enable` | `true` | the org look for site and deck (org CSS, custom palette) |
| `mermaid.enable` | a page under `docs/` has a ` ```mermaid ` block | ship Mermaid with the site so diagrams render offline |
| `strict` | `true` | `mkdocs --strict` in build and preview |
| `port` | `8981` | live docs preview |
| `extraPythonPackages` | `ps: []` | more MkDocs plugins from `python3Packages` |
| `slides.enable` | `documentation/slides/` exists | deck + `apps.serve-slides` |
| `slides.dir` | `"${root}/slides"` | deck directory |
| `slides.path` | `slides.dir` relative to the repo | where the live preview serves from |
| `slides.embed` | `true` | copy the deck into the site at `slides/` |
| `slides.markdown` | `"slides.md"` | the deck's Markdown file |
| `slides.title` | `settings.site_name` | deck page title |
| `slides.theme` | `"black"` | base reveal.js theme, under the org style |
| `slides.config` | org defaults (below) | `Reveal.initialize` options |
| `slides.speakerSync` | `true` | audience window follows the speaker view without lag |
| `slides.sketch.enable` | `true` | redraw `svg.sketch` diagrams with rough.js |
| `slides.extraHead` | `""` | extra `<head>` tags, after the org style |
| `slides.extraBody` | `""` | extra tags after reveal.js and its plugins, before `Reveal.initialize` |
| `slides.port` | `8982` | live slides preview |

Org `settings` defaults:

- `site_name`: `external-systems <repo>`, or `Documentation`.
- `use_directory_urls: false`.
- `theme`: material, `font: false`; features content.code.annotate/copy,
  content.tooltips, navigation.footer/indexes/sections/top,
  search.highlight/suggest, toc.follow; light and dark palette (primary
  and accent `custom` with the org style).
- `plugins: [search, offline]`.
- `markdown_extensions`: abbr, admonition, attr_list, md_in_html, tables,
  pymdownx.details/highlight/keys, pymdownx.emoji (twemoji, SVG),
  pymdownx.superfences with the `mermaid` fence, pymdownx.tabbed
  (alternate_style), toc (permalink).
- Added by the build, not by `settings`: `theme.custom_dir` (org files),
  `extra_css` gets `stylesheets/org.css` first, `extra_javascript` gets
  `javascripts/mermaid.min.js` when Mermaid is on. A repo's own entries
  are appended.

Org `slides.config` defaults: `hash = true`, `slideNumber = "h.v"`,
`progress = true`, `transition = "slide"`, `backgroundTransition =
"fade"`, `autoAnimateDuration = 0.8`, `width = 1280`, `height = 720`.
Plugins are always Markdown, Highlight (monokai) and Notes.
