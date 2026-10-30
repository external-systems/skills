---
name: devenv
description: "devenv 2.x dev environments: full CLI reference, devenv.yaml inputs/lock discipline, CLI-native vs flake embedding (and why CLI is the default for dev shells), the borg hybrid pattern (one shared module, two lockfiles, drift check), devcontainer.json, monorepo/polyrepo, containers/OCI/K8s, and the Claude Code integration. Load when writing devenv.nix/devenv.yaml/.devcontainer or running devenv commands."
---

# devenv

devenv declares complete development environments (packages, languages,
services, processes, tasks, secrets) in Nix, reproducibly and fast. This
reference brings an agent up to speed on devenv 2.x (the v2 interface to
Nix) so it can author and maintain dev shells, generate
devcontainer.json, run CLI commands, and compose environments without
re-reading the docs.

Version alert: devenv 2.x is a major redesign (2.0 released March 2026,
2.3 September 2026). Local CLI on this machine and the worked example
repo are both pinned at **v2.3.1**. Much older training-data advice
(process-compose defaults, direnv-only activation, `pre-commit`, plain
`devenv build` output) is stale — see the [v2 alert](#devenv-2x-alert)
below. Canonical docs live at https://devenv.sh; a full doc map is at
the end of this file.

## Mental model

Three files define a project, plus generated state:

- **`devenv.nix`** — the environment: a Nix function returning a module
  (`{ pkgs, ... }: { ... }`). One concern per import; merge via
  `imports`.
- **`devenv.yaml`** — project settings: `inputs` (dependencies),
  `imports` (shared configs), nixpkgs config, shell/profile/reload
  behavior.
- **`devenv.lock`** — resolved input revisions. Committed; hand edits
  are a smell — update with `devenv update` or `devenv inputs add`.
- **`.devenv/`** — runtime state (profile, caches, task/process state).
  Gitignore it; never commit.

Special arguments every `devenv.nix` module receives: `pkgs` (the
`nixpkgs` input for your system), `inputs` (all devenv.yaml inputs),
`config` (the final resolved configuration — reference any option
lazily), `lib` (nixpkgs lib), and `multiverse` (when configured —
version-pinned packages, see
[pinning](https://devenv.sh/pinning/)).

Scaffold a new project with `devenv init` (writes `devenv.yaml`,
`devenv.nix`, `.gitignore`; `--include-envrc` adds an `.envrc` for
direnv).

Two usage modes exist and they compose:

1. **CLI-native mode** (default, recommended by upstream): root
   `devenv.nix`/`devenv.yaml`, activated with `devenv shell` / auto
   activation. Full feature set: containers, evaluation caching, GC
   protection, cross-project references, secretspec, fast startup.
2. **Embedded-in-a-flake mode**: the devenv module system evaluated
   inside `nix develop` via `inputs.devenv.flakeModule` (flake-parts)
   or `devenv.lib.mkShell` (plain flake). Use when the project already
   is a flake. Limitations: needs `--no-pure-eval` (or a `devenv.root`
   override), no container outputs unless you add nix2container,
   slower eval, no process running in `devenv test`. Feature table
   below.

The two modes can be combined so one shared module feeds both — that is
exactly what the borg repo does (see [the worked
example](#worked-example-borg)). Why the CLI is the better default for
the day-to-day dev shell even in a flake repo: the flake embedding
gains nothing for plain shell entry (`nix develop` vs `devenv shell`)
while giving up the CLI's container builds, eval caching, GC
protection, and cross-project references; upstream's own template set
(`devenv init`, `devenv generate`) assumes CLI-native mode. Keep flake
`devShells` only where CI or flake consumers need the shell as an
output.

## devenv 2.x alert

Read this before writing process definitions or scripts. What changed:

| Version | Headline changes |
|---|---|
| 2.0 (2026-03) | Rust rewrite. Native process manager replaces process-compose (still selectable). Hot reload, TUI, automatic port allocation, `devenv hook` auto-activation (no direnv needed), bundled MCP server, quiet mode for coding agents. |
| 2.1 (2026-05) | Native zsh/fish/nushell via libghostty; auto-reload applies env at next prompt; `devenv processes list/status/logs/restart/start/stop`; OTLP trace export (`--trace-to`). |
| 2.2 (2026-07) | `devenv up` **attaches** to a running manager; `--from` sources bind to a directory persistently (`devenv allow`); `devenv down`; SecretSpec 0.17 + Cachix token via secretspec. Breaking: x86_64-darwin dropped; hook detects `devenv.nix` (not `devenv.yaml`). |
| 2.3 (2026-09) | Portless URLs: stable `<process>.<project>.localhost` via built-in proxy; TUI/shell user config (`~/.config/devenv/config.yaml`); `multiverse.pins` resolves many version pins at once; Linux capabilities for processes; `devenv hook <shell> -- --no-tui` argument forwarding. |

Breaking changes to watch in existing code and scripts:

- **git-hooks input is no longer implicit.** If you use
  `git-hooks.hooks`, declare it in `devenv.yaml`:

  ```yaml
  inputs:
    git-hooks:
      url: github:cachix/git-hooks.nix
  ```

- **`pre-commit` renamed to `prek`** in scripts and hooks
  (`prek run --all-files`).
- **`devenv build` returns JSON** — parse with
  `devenv build languages.rust.package | jq -r '.["languages.rust.package"]'`.
- **`devenv container --copy <name>` removed** — use
  `devenv container copy <name>`.
- **Process-compose-only options are gone** unless you opt back in with
  `process.manager.implementation = "process-compose";` — migrate with
  the table below.
- `processes.<name>.shutdown.signal`/`.grace` exist only from 2.2.3
  (older 2.x always SIGTERMs).

process-compose → native manager migration (apply only the parts you
used):

| Before (`processes.<name>.process-compose.*`) | After (`processes.<name>.*`) |
|---|---|
| `depends_on.X.condition = "process_healthy"` | `after = [ "devenv:processes:X" ]` (X needs a `ready` probe) |
| `depends_on.X.condition = "process_completed_successfully"` | `after = [ "devenv:processes:X@succeeded" ]` |
| `depends_on.X.condition = "process_completed"` | `after = [ "devenv:processes:X@completed" ]` |
| `depends_on.X.condition = "process_started"` | `after = [ "devenv:processes:X@started" ]` |
| `availability.restart = "on_failure"`, `max_restarts = 5` | `restart = { on = "on_failure"; max = 5; }` (`never`/`always`/`on_failure`, optional `window`) |
| `environment = [ "FOO=bar" ]` | `env.FOO = "bar";` |
| `working_dir = "/app"` | `cwd = "/app";` |
| `readiness_probe.exec.command = "curl -f ..."` | `ready.exec = "curl -f ...";` (+ `ready.period`, `ready.failure_threshold`) |
| — (native-only) | `ready.http.get = { port = 8080; path = "/health"; };` |
| — (native-only) | `ready.notify = true;` (sd_notify READY=1) |
| `liveness_probe` | `watchdog.usec = 30000000;` + heartbeat `WATCHDOG=1` via NOTIFY_SOCKET |
| `is_elevated = true` | `linux.capabilities = [ "net_bind_service" ];` (sudo on first launch) |
| `shutdown.signal = 2` | `shutdown.signal = 2;` (2.2.3+, applies to both managers) |

## devenv.yaml: inputs, imports, settings

Default inputs when no `devenv.yaml` exists:

```yaml
inputs:
  nixpkgs:
    url: github:cachix/devenv-nixpkgs/rolling
  git-hooks:
    url: github:cachix/git-hooks.nix
```

`devenv-nixpkgs/rolling` is a fork tested against devenv's suite with
monthly updates. Add a second input for bleeding-edge packages:

```yaml
inputs:
  nixpkgs-unstable:
    url: github:NixOS/nixpkgs/nixpkgs-unstable
```

```nix
# devenv.nix — use a second nixpkgs for fast-moving packages
{ pkgs, inputs, ... }: {
  packages = [ (import inputs.nixpkgs-unstable {
    system = pkgs.stdenv.system;
  }).elmPackages.elm-test-rs ];
}
```

Per-input options:

| Option | Purpose |
|---|---|
| `url` | Nix flake URI (see below) |
| `follows` | Inherit another input (`nixpkgs.follows: base-project/nixpkgs`) to deduplicate |
| `inputs.<name>.follows` | Override a nested input of this input (e.g. pin git-hooks' nixpkgs) |
| `overlays` | List of overlays to pull from the input |
| `flake` | `false` when the input is a plain `devenv.nix` project, not a flake |

Common URI formats: `github:org/repo/branch`,
`github:org/repo?ref=v1.0.0`, `github:org/repo?dir=subdir`,
`gitlab:owner/repo/branch`,
`git+https://host/user/path?ref=branch&rev=<rev>`,
`git+ssh://...`, `tarball+https://...`, `path:/local/dir` (local paths
copy the whole directory — prefer `git+file:` for large trees).

Manage inputs from the CLI instead of hand-editing:

```console
devenv inputs add nixpkgs-stable github:NixOS/nixpkgs/nixos-25.05
devenv inputs add my-input github:org/repo --follows nixpkgs
devenv update      # resolve/update devenv.lock
```

Other `devenv.yaml` settings worth knowing: `imports` (list of paths or
input names — absolute paths starting with `/` resolve from the repo
root), `nixpkgs.allow_unfree`, `nixpkgs.permitted_unfree_packages`,
`nixpkgs.permitted_insecure_packages`, `nixpkgs.allow_broken`,
`clean.enabled`/`clean.keep`, `impure`, `profile` (default profile),
`shell` (`bash`/`zsh`/`fish`/`nu`), `reload`, `strict_ports`,
`require_version`, `prompt_prefix`, `secretspec.*`. Full reference:
https://devenv.sh/reference/yaml-options/

## CLI reference (devenv 2.3.1)

| Command | What it does |
|---|---|
| `devenv init` | Scaffold devenv.yaml, devenv.nix, .gitignore (`--include-envrc` adds .envrc) |
| `devenv generate` | Generate devenv.yaml + devenv.nix from an AI prompt |
| `devenv shell` | Enter the environment; `devenv shell -- <cmd>` runs a command inside |
| `devenv up` | Start processes (attaches to running manager in 2.2+); `-d` detaches |
| `devenv down` | Stop the process manager and its processes |
| `devenv processes` | `list` / `status` / `logs <name>` / `restart <name>` / `start <name>` / `stop <name>` / `attach` / `down` |
| `devenv tasks run <id>` | Run tasks; `devenv tasks list [--json]` shows the graph |
| `devenv test` | Run tests with processes active |
| `devenv search <term>` | Search packages AND devenv options for your pinned nixpkgs |
| `devenv info` | Print env/packages/scripts/processes summary |
| `devenv update` | Update devenv.lock from devenv.yaml inputs |
| `devenv inputs add <name> <url>` | Add/follow an input without hand-editing yaml |
| `devenv build <attr>` | Build any attribute (JSON output in 2.x) |
| `devenv eval <attr>` | Evaluate any attribute as JSON |
| `devenv container` | `build` / `copy` / `run` a container |
| `devenv repl` | Interactive REPL exposing `devenv`, `pkgs`, `inputs` |
| `devenv mcp` | Serve an MCP server (search options/packages) for AI assistants |
| `devenv lsp` | Start nixd language server for devenv.nix |
| `devenv gc` | Delete old shell generations (batched, needs Nix ≥ 2.35 for speed) |
| `devenv changelogs` | Show relevant changelogs for your modules |
| `devenv direnvrc` | Print direnvrc that adds devenv support to direnv |
| `devenv hook <shell>` | Print the auto-activation hook (`bash`/`zsh`/`fish`/`nu`) |
| `devenv allow` / `devenv revoke` | Trust / untrust the current directory for auto-activation |
| `devenv user-config` | Inspect/validate `~/.config/devenv/config.yaml` |

Global flags:

- `-O <attr>:<type> <value>` — ad-hoc option overrides without a
  `devenv.nix`, e.g.
  `devenv -O languages.rust.enable:bool true shell -- cargo build`
- `--from path:/abs/dir` or `--from github:org/repo?dir=subdir` — use a
  foreign devenv; bind it persistently with `devenv allow`
- `-o, --override-input <name> <uri>` — CI overrides without editing
  yaml
- `--profile <name>` (repeatable), `--shell bash|zsh|fish|nu`
- `--reload` / `--no-reload`, `--strict-ports` / `--no-strict-ports`
- `--trace-to otlp-grpc` etc. (observability), `--verbose`, `--tui`
- `--user-config <file>`

Agent-relevant behavior: devenv detects coding agents (`CLAUDECODE`,
`OPENCODE_CLIENT`, `AI_AGENT`) and switches to quiet mode (no TUI
output); opt out with `DEVENV_NO_AI_AGENT=1`. `devenv mcp` exposes
options/packages search and process tools to MCP clients — in this
fleet it is wired for opencode (the `devenv` MCP server) in
`flake-parts/homeModules/agents.nix`, and the home repo ships a
pinned fallback project (`~/.config/devenv-agent`) so the MCP works
even outside a devenv project.

## devenv.nix essentials

```nix
{ pkgs, config, ... }: {
  env.GREET = "hello";

  packages = [ pkgs.jq ];

  enterShell = ''
    echo $GREET
    jq --version
  '';

  scripts."my-script".exec = "echo doing things";
}
```

- `enterShell` runs bash once on activation; for ordered/parallel setup
  prefer `tasks` (`tasks."<id>".exec` with `before`/`after` on
  `devenv:enterShell`).
- `devenv shell -- git log --oneline` runs a command in the env and
  exits; wrap compound commands:
  `devenv shell -- bash -c 'cd src && make'`.
- `devenv info` prints env, packages, scripts, processes.
- Hide the `(devenv)` prompt prefix (e.g. with Starship):
  `prompt_prefix: false` in `devenv.yaml` (or globally in
  `~/.config/devenv/config.yaml` under `shell.prompt_prefix`).
- Skip the C toolchain when not needed: `stdenv = pkgs.stdenvNoCC;`
  (saves hundreds of MB and startup time).
- Escape Nix interpolation inside scripts with `''${var}`.

Languages and services are the backbone:
`languages.rust.enable = true;`,
`services.postgres.enable = true;` etc. Every option is documented at
https://devenv.sh/reference/options/ and every language/service has a
dedicated page (https://devenv.sh/languages/,
https://devenv.sh/services/).

## Using with flake-parts

`devenv` ships a flake-parts module. Quick template:
`nix flake init --template github:cachix/devenv#flake-parts`.

```nix
# flake.nix
{
  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    devenv.url = "github:cachix/devenv";
    nixpkgs.url = "github:cachix/devenv-nixpkgs/rolling";
  };

  outputs = inputs @ {flake-parts, ...}:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [inputs.devenv.flakeModule];
      systems = ["x86_64-linux"];

      perSystem = {config, ...}: {
        devenv.shells.default = {
          imports = [ ./devenv.nix ];
          packages = [ config.packages.default ];
        };

        devShells.default = config.devenv.shells.default;  # optional alias
      };
    };
}
```

- Enter with `nix develop --no-pure-eval` — flakes are pure-eval and
  devenv needs to query the working directory. Alternative: set
  `devenv.root` to an absolute path in the shell module (makes the
  flake machine-specific but pure-safe).
- `devenv up` / `devenv test` still work from the flake shell.
- Multiple shells: define `devenv.shells.projectA` /
  `devenv.shells.projectB` and pick a default with
  `devShells.default = config.devShells.projectA;`. Enter with
  `nix develop --no-pure-eval .#projectA`.
- Under direnv, `devenv up`, `devenv test`, and `devenv tasks` skip
  re-evaluation and hit the cache (significantly faster).
- The flake-parts module auto-generates `container-shell` /
  `container-processes` package outputs per shell; they throw at eval
  time unless `nix2container` and `mk-shell-bin` are flake inputs. If
  you have no devenv-container use case, suppress them with
  `containers = lib.mkForce {};`.

### Worked example: borg

The borg repo (`andrewthomaslee/borg`) wires devenv in **both modes
from one shared module** — the pattern to copy:

1. **Flake-parts mode** (`nix develop`): `flake.nix` pins
   `devenv.url = "github:cachix/devenv?ref=v2.3.1";` and imports
   `inputs.devenv.flakeModule`. `flake-parts/devShells.nix` declares
   the shell and a cacheable package alias:

   ```nix
   # flake-parts/devShells.nix
   _: {
     perSystem = {self', ...}: {
       packages.devShell = self'.devShells.default;
       devenv.shells.default = {
         imports = [../devenv];
       };
     };
   }
   ```

2. **CLI mode** (`devenv shell`, `devenv mcp`, auto-activation): root
   `devenv.nix` imports the same directory and layers overlays that
   need devenv.yaml inputs:

   ```nix
   # devenv.nix (repo root)
   {inputs, ...}: {
     imports = [./devenv];

     overlays = [
       (_final: prev: {
         clan-cli = inputs.clan-core.packages.${prev.stdenv.hostPlatform.system}.clan-cli;
       })
     ];
   }
   ```

3. **devenv.yaml** pins its inputs to the *exact* nixpkgs/clan-core
   revisions flake.lock holds, so both lockfiles reference identical
   sources (same builds, shared `devenv.cachix.org` cache):

   ```yaml
   inputs:
     nixpkgs:
       url: github:NixOS/nixpkgs/<rev-from-flake.lock>
     clan-core:
       url: git+https://git.clan.lol/clan/clan-core?ref=26.05&rev=<rev>
   nixpkgs:
     allow_unfree: true
   ```

4. **Discipline:** a `devenv-lock-drift` check in
   `flake-parts/checks.nix` fails when `devenv.yaml` pins drift from
   `flake.lock` — bump nixpkgs/clan-core and the pinned URLs (plus
   `devenv update`) in the same commit.

The shared module (`devenv/default.nix`) carries the gotchas worth
copying:

```nix
{pkgs, lib, ...}: {
  packages = [ /* shared tool set */ ];

  devenv.root = let
    pwd = builtins.getEnv "PWD";
  in
    if pwd == ""
    then "/tmp/devenv-pure-root"   # writable scratch for pure evals
    else pwd;

  containers = lib.mkForce {};

  dotenv.disableHint = true;

  enterShell = ''
    export REPO_ROOT="$(git rev-parse --show-toplevel)"
  '';
}
```

Hard rule in that repo: the shared module must not reference flake-only
things (`inputs`, `self'`) — it evaluates inside devenv's own module
system where `inputs` means *devenv.yaml inputs*, not the flake's. Entry
points that need flake values inject them via overlays (`devenv.nix`)
or let flake-parts resolve `pkgs`.

Why the two-lockfile hybrid instead of just flake devShells: CLI mode
keeps full devenv features (processes, containers, GC protection, MCP,
auto-activation) while `nix develop` keeps flake consumers and CI on
standard outputs — one shared module, identical pin sets, zero drift
thanks to the check.

## Using with flakes (plain, no flake-parts)

Use `devenv.lib.mkShell` when you cannot or do not want flake-parts:

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:cachix/devenv-nixpkgs/rolling";
    devenv.url = "github:cachix/devenv";
  };

  nixConfig = {
    extra-trusted-public-keys = "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=";
    extra-substituters = "https://devenv.cachix.org";
  };

  outputs = {self, nixpkgs, devenv, ...} @ inputs: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    devShells.${system}.default = devenv.lib.mkShell {
      inherit inputs pkgs;
      modules = [ { packages = [ pkgs.hello ]; } ];
    };
  };
}
```

Multiple shells:
`devShells.${system}.projectA = devenv.lib.mkShell {...};` entered with
`nix develop --no-pure-eval .#projectA`.

What the dedicated CLI gives you that embedded-flake shells do not:
built-in container support, GC protection, evaluation caching +
lazy-tree fast eval, cross-project references, secretspec, and running
processes under `devenv test`. If you only ever run `nix develop`, the
flake embedding is fine; for anything richer, prefer CLI-native mode.
External flakes
(`nix develop --no-pure-eval file:/path/to/central/flake#projectA`)
work for projects that cannot carry their own `flake.nix` — no
lockfile means unpinned versions, so prefer a local project flake.

## devcontainer.json and GitHub Codespaces

devenv autogenerates a devcontainer from your environment:

```nix
# devenv.nix
{
  devcontainer.enabled = true;
}
```

Run `devenv shell` — it writes `.devcontainer/devcontainer.json`.
Commit and push it; GitHub Codespaces (and any devcontainer-compatible
editor) then builds your environment from it.

`devcontainer.settings` is freeform JSON with these defaults (from the
devenv module source):

| Setting | Default |
|---|---|
| `image` | `ghcr.io/cachix/devenv/devcontainer:latest` |
| `overrideCommand` | `false` |
| `updateContentCommand` | `"devenv test"` |
| `customizations.vscode.extensions` | `[ "mkhl.direnv" ]` |
| `customizations.zed.extensions` | `[]` |

The image ships the devenv CLI, so anything in `devenv.nix` —
languages, services, tasks — works inside the container; the direnv
VS Code extension keeps the editor shell in sync. Add extra JSON
settings (ports, features, more extensions) freely via
`devcontainer.settings`.

## Monorepo

Share one config across many services (new in 1.10). Layout:

```text
my-monorepo/
├── shared/devenv.nix        # common packages, services, git-hooks
└── services/
    ├── api/devenv.yaml      # imports: - /shared
    ├── api/devenv.nix
    ├── frontend/devenv.yaml # imports: - /shared
    └── frontend/devenv.nix
```

- `imports: [ "/shared" ]` — paths starting with `/` resolve from the
  repository root (where `.git` lives), so every service can reference
  shared configs consistently.
- Enter a service env with `cd services/api && devenv shell`; it gets
  shared + own configuration merged.
- Reference the repo root with `config.git.root` when processes need
  working directories:

  ```nix
  # services/api/devenv.nix
  { config, ... }: {
    processes.api.exec = {
      exec = "npm run dev";
      cwd = "${config.git.root}/services/api";
    };
  }
  ```

- Profiles layer on top for team/environment variants
  (`devenv --profile backend shell`) — often a better fit than more
  imports. See https://devenv.sh/profiles/

## Polyrepo

Compose environments across repositories. Two approaches:

1. **Merge everything via imports** — add the remote as an input and
   import it; its packages, services, env, outputs, processes all
   merge:

   ```yaml
   # devenv.yaml
   inputs:
     my-service:
       url: github:myorg/my-service
   imports:
     - my-service
   ```

   ```nix
   # devenv.nix
   { config, ... }: {
     packages = [ config.outputs.my-service ];
   }
   ```

2. **Reference specific config without merging** (new in 2.0) — access
   `inputs.<name>.devenv.config.<option>`; the input must be
   `flake: false`:

   ```yaml
   inputs:
     my-service:
       url: github:myorg/my-service
       flake: false
   ```

   ```nix
   { inputs, ... }: {
     packages = [ inputs.my-service.devenv.config.outputs.my-service ];
   }
   ```

Caveats to respect:

- Imported remote projects must use `devenv.nix` only — their
  `devenv.yaml` is *not* evaluated (upstream issue #2205).
- Profiles do not work with cross-project references (#2521).
- The remote project's `outputs.<name>` pattern
  (`config.languages.python.import ./. {}`) is how it exposes
  buildables.

## Cross-platform patterns

Condition on the machine with `pkgs.stdenv`:

```nix
{ pkgs, lib, ... }: {
  packages = [
    pkgs.ncdu
  ] ++ lib.optionals pkgs.stdenv.isLinux [ pkgs.inotify-tools ]
    ++ lib.optionals pkgs.stdenv.isDarwin [ pkgs.libiconv ];
}
```

Helpers: `stdenv.isLinux`, `stdenv.isDarwin`, `stdenv.isAarch64`,
`stdenv.isx86_64`. Use `lib.optionalAttrs` for per-platform attribute
merges inside existing options.

When whole configuration sections differ per platform, do NOT use `//`
/ `optionalAttrs` at the top level — the keys of the attrset would
depend on values inside it, and Nix dies with `infinite recursion`.
Use module helpers instead:

```nix
{ pkgs, lib, ... }: {
  packages = [ pkgs.git ];
}
# ❌ fails: { ... } // lib.optionalAttrs pkgs.stdenv.isLinux { ... }
# ✅ top-level becomes:
lib.mkMerge [
  { packages = [ pkgs.git ]; }
  (lib.mkIf pkgs.stdenv.isLinux {
    packages = [ pkgs.ncdu ];
    env.SOME_VAR = "linux-only";
  })
]
```

## Containers

Two distinct things — do not confuse them.

### Ephemeral environments for humans, agents, CI, and Kubernetes

- **Ad-hoc shells** (`devenv -O ... shell -- <cmd>`): spin a throwaway
  environment around any command without a project `devenv.nix` —
  instant ephemeral coding environments for a human trying a tool or an
  agent that needs a missing tool; composes multiple option overrides
  (see the Global flags above and
  https://devenv.sh/ad-hoc-developer-environments/).
- **Project shells** (`devenv shell` in a checked-out project): the
  reproducible daily-driver environment; agents work inside it like any
  developer.
- **Profiles** (`devenv --profile <name> shell`): variants of one
  project environment (minimal vs full, backend vs frontend) — pick
  per-consumer without new files.

### Building OCI images from the environment

Requires the container inputs once:

```console
devenv inputs add nix2container github:nlewo/nix2container --follows nixpkgs
devenv inputs add mk-shell-bin github:rrbutani/nix-mk-shell-bin
```

Then: `devenv container build shell` (enter the environment),
`devenv container build processes` (run your processes as the
entrypoint), `devenv container run <name>` (via Docker),
`devenv container --registry docker://ghcr.io/ copy <name>` (push via
skopeo; customize with `containers.<name>.registry` /
`.defaultCopyArgs`). Custom containers:

```nix
{
  containers."prod" = {
    copyToRoot = ./dist;
    startupCommand = "/mybinary serve";
  };
}
```

- `config.container.isBuilding` /
  `config.containers."<name>".isBuilding` let you exclude dev-only
  packages from images.
- Building containers on macOS requires a remote Linux builder.

### Running devenv itself in containers (CI, Kubernetes, Argo)

The official [devenv container
image](https://devenv.sh/integrations/devenv-container/)
(`ghcr.io/cachix/devenv/devenv:latest`) runs devenv commands on any
container-based system — Docker, GitLab CI, Kubernetes Jobs
(`command: ["devenv", "tasks", "run", "my-app:hello-world"]`), and
equivalently Argo Workflows: there is no dedicated Argo page; map the
Kubernetes Job pattern onto your Argo Workflow container spec the same
way (`image: ghcr.io/cachix/devenv/devenv:latest`,
`command: devenv ...`). Full examples:
https://devenv.sh/integrations/devenv-container/

## Claude Code integration

Global setup — tell Claude to reach for devenv when tools are missing
(`~/.claude/CLAUDE.md`):

```markdown
When devenv.nix doesn't exist and a command/tool is missing, create ad-hoc
environment:

    $ devenv -O languages.rust.enable:bool true -O packages:pkgs "mypackage mypackage2" shell -- cli args

When the setup becomes complex create `devenv.nix` and run commands within:

    $ devenv shell -- cli args

See https://devenv.sh/ad-hoc-developer-environments/
```

Per-project integration (`claude.code.enable = true;`) wires:

- **Auto-formatting** — git-hooks run on files Claude edits
- **Hooks** — `PreToolUse` (can block), `PostToolUse`, `Notification`,
  `Stop`, `SubagentStop`; each takes `matcher` (regex on tool name) and
  `command` (reads hook JSON from stdin)
- **Commands** — `claude.code.commands.<name>` become `/name` slash
  commands
- **Agents** — `claude.code.agents.<name>` with `description`, `tools`,
  `model`, `effort`, `prompt`, `permissionMode`; `claude.code.agent`
  promotes one to primary
- **Skills** — `claude.code.skills.<name>` writes
  `.claude/skills/<name>/SKILL.md` with `description`, `content`,
  `resources` (long reference material), `allowedTools`,
  `copyMode = "seed"` to edit in place
- **MCP servers** — `claude.code.mcpServers` (stdio or http) generates
  `.mcp.json`; include devenv itself with
  `{ type = "stdio"; command = "devenv"; args = [ "mcp" ]; }`

Full reference: https://devenv.sh/integrations/claude-code/

## Where to read more

| Topic | URL |
|---|---|
| Getting started / basics | https://devenv.sh/getting-started/ · https://devenv.sh/basics/ |
| All devenv.nix options | https://devenv.sh/reference/options/ |
| All devenv.yaml options | https://devenv.sh/reference/yaml-options/ |
| Inputs & locking | https://devenv.sh/inputs/ |
| Packages & search | https://devenv.sh/packages/ |
| Languages / Services | https://devenv.sh/languages/<name>/ · https://devenv.sh/services/<name>/ |
| Processes (native manager) | https://devenv.sh/processes/ |
| Tasks | https://devenv.sh/tasks/ |
| Tests | https://devenv.sh/tests/ |
| Profiles | https://devenv.sh/profiles/ |
| Outputs (packaging) | https://devenv.sh/outputs/ |
| Version pinning (multiverse) | https://devenv.sh/pinning/ |
| Containers | https://devenv.sh/containers/ |
| devenv-container CI image | https://devenv.sh/integrations/devenv-container/ |
| Auto-activation | https://devenv.sh/auto-activation/ |
| direnv | https://devenv.sh/integrations/direnv/ |
| Imports (monorepo/polyrepo) | https://devenv.sh/composing-using-imports/ |
| Flake guides | https://devenv.sh/guides/using-with-flakes/ · https://devenv.sh/guides/using-with-flake-parts/ |
| v2 migration guide | https://devenv.sh/guides/migrating-to-20/ |
| Monorepo / Polyrepo guides | https://devenv.sh/guides/monorepo/ · https://devenv.sh/guides/polyrepo/ |
| Recipes (nix, containers, cross-platform) | https://devenv.sh/recipes/ |
| Release notes / blog | https://devenv.sh/blog/ (2.0: 2026-03-05, 2.1: 2026-05, 2.2: 2026-07, 2.3: 2026-09) |
| Ad-hoc environments | https://devenv.sh/ad-hoc-developer-environments/ |
| TUI & user config | https://devenv.sh/tui-customization/ |
| Garbage collection | https://devenv.sh/garbage-collection/ |
| Examples library | https://devenv.sh/examples/ · https://github.com/cachix/devenv/tree/main/examples |
| Claude Code integration | https://devenv.sh/integrations/claude-code/ |
| Codespaces / devcontainer | https://devenv.sh/integrations/codespaces-devcontainer/ |
| Full changelog | https://github.com/cachix/devenv/blob/main/CHANGELOG.md |
