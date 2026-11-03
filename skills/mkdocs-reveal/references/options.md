# docs.* options (pkgs flakeModules.docs)

All under `perSystem.docs`. Source of truth: `flakeModules/docs.nix` in
external-systems/pkgs, and its docs page "Docs and slides".

| Option | Default | Meaning |
| --- | --- | --- |
| `enable` | `documentation/docs/` exists (and presenting not imported) | site + `apps.watch-documentation` |
| `root` | `"${self}/documentation"` | documentation directory |
| `path` | `root` relative to the repo | where the live preview serves from |
| `repo` | `null` | org repo name: `site_url`, `repo_url`, `repo_name`, `edit_uri` |
| `settings` | org defaults | mkdocs.yml as Nix (freeform), merged with `mkDefault` defaults |
| `strict` | `true` | `mkdocs --strict` in build and preview |
| `port` | `8981` | live docs preview |
| `extraPythonPackages` | `ps: []` | more MkDocs plugins from `python3Packages` |
| `slides.enable` | `documentation/slides/` exists (and presenting not imported) | deck + `apps.serve-slides` |
| `slides.dir` | `"${root}/slides"` | deck directory |
| `slides.path` | `slides.dir` relative to the repo | where the live preview serves from |
| `slides.embed` | `true` | copy the deck into the site at `slides/` |
| `slides.markdown` | `"slides.md"` | the deck's Markdown file |
| `slides.title` | `settings.site_name` | deck page title |
| `slides.theme` | `"black"` | reveal.js theme (`white`, `league`, `moon`, `dracula`, ...) |
| `slides.config` | `{hash = true; slideNumber = true;}` | `Reveal.initialize` options |
| `slides.extraHead` | `""` | extra `<head>` tags in the generated page |
| `slides.port` | `8982` | live slides preview |

Org `settings` defaults: `site_name` (`external-systems <repo>` or
`Documentation`), `use_directory_urls: false`, `theme` (material, `font:
false`, features: content.code.annotate/copy, navigation.footer/indexes/
sections/top, search.highlight/suggest, toc.follow; light/dark palette),
`plugins: [search, offline]`, `markdown_extensions`: admonition,
attr_list, md_in_html, tables, pymdownx.details/highlight/keys/
superfences, pymdownx.tabbed (alternate_style), toc (permalink).
