# Writing in the org style

The deck is `documentation/slides/slides.md`; reveal.js reads it as
Markdown with HTML allowed. Source of the classes below: pkgs
`flakeModules/docs/org/slides.css` (served as `org/org.css`).

## Slide structure

| In slides.md | Means |
| --- | --- |
| `---` on its own line | next slide (to the right) |
| `--` on its own line | slide below (detail the audience can skip) |
| `Note:` | speaker notes to the end of the slide (press S) |
| `<!-- .slide: class="title-slide" -->` | a class or `data-*` on the slide |
| `<!-- .element: class="fragment" -->` | a class on the element just before it |
| `<!-- .slide: data-auto-animate -->` | morph matching elements into the next slide |

Keys while presenting: S speaker view (synced), F fullscreen, Esc
overview, arrows to move.

## Building blocks

| Class | Use |
| --- | --- |
| `kicker` | small uppercase clay line above a title (`<p class="kicker">Part 2</p>`) |
| `big` | one large statement |
| `hint` | a small muted line at the bottom |
| `muted`, `<small>` | secondary text |
| `takeaway` | the one line to remember, in a clay-edged box |
| `layer` | a row in a stacked layer cake: `<div class="layer"><span>Name</span><span>what it does</span></div>`, top to bottom |
| `title-slide` | on a slide: bigger h1, no underline on h2 |
| `pre.spec` | a short YAML or pseudocode listing without a code block: `<pre class="spec"><span class="k">kind:</span> <span class="v">Site</span> <span class="c"># comment</span></pre>`; `.kw` for keywords |
| `ul.ticks` / `ul.ticks.cross` | ✓ / ✗ checklist |
| `img.icon` | an inline logo at text height; `img.hero` a big one above a title |
| `tiles` + `tile` | a centred row of logo tiles: `<div class="tile"><img src="icons/x.svg"><b>Name</b><span>one line</span></div>` |
| `diagram` + `svg.sketch` | a hand-drawn diagram (below) |

Markdown tables, `**bold**` (clay) and `*em*` (sand) are styled too.
Fragments (`class="fragment fade-up"`) work on any of them; put the
fragment on a wrapper `<g>` in a diagram, never on a shape.

A deck's own blocks go in its `custom.css` (loaded after `org.css`) and
use the org variables: `--bg`, `--bg-deep`, `--surface`, `--surface-2`,
`--cream`, `--muted`, `--clay`, `--clay-soft`, `--blue`, `--green`,
`--sand`, `--rose`.

## Sketch diagrams

Draw with plain SVG; once the deck is ready, every `rect`, `ellipse`,
`circle`, `line` and `polyline` inside an `svg.sketch` is redrawn with
rough.js so it looks drawn by hand. `<text>` and `<image>` stay crisp.

```html
<div class="diagram">
<svg class="sketch" viewBox="0 0 600 160">
  <rect x="20" y="40" width="200" height="80" stroke="#d97757" fill="#d97757" />
  <text x="120" y="88" text-anchor="middle">Desired state</text>
  <g class="fragment fade-in">
    <line x1="230" y1="80" x2="370" y2="80" stroke="#faf9f5" data-arrow />
    <rect x="380" y="40" width="200" height="80" stroke="#6a9bcc" fill="none" data-dash />
    <text x="480" y="88" text-anchor="middle">Actual state</text>
  </g>
</svg>
</div>
```

| Attribute | Effect |
| --- | --- |
| `stroke`, `stroke-width` | line colour and width |
| `fill` | a soft flat tint, so text on top stays readable; `fill="none"` outline only |
| `data-fill="solid"` | the fill at full strength |
| `rx` | rounded corners on a rect (default 12) |
| `data-arrow` | arrowhead at the end of a line or polyline |
| `data-dash` | dashed outline |
| `class="mono"` / `"sans"` on text | font family |

Keep the `viewBox` near the slide's 1280×720 proportions and size text in
viewBox units.

## Site pages

Material for MkDocs Markdown, with the org extensions on:

- Admonitions: `!!! note "Title"`, collapsible `??? tip`.
- Tabs: `=== "Windows"` blocks.
- Keys: `++ctrl+c++`.
- Emoji and icons: `:material-kubernetes:`, `:fontawesome-brands-github:`.
- Abbreviations: `*[API]: Application Programming Interface`.
- Mermaid: a fenced block with the language `mermaid`; it renders
  offline because Mermaid ships with the site.
- Attributes on elements: `{ .class }` (attr_list), Markdown inside HTML
  with `markdown`.

A page shows the deck with an iframe (`slides/index.html`, see SKILL.md).
