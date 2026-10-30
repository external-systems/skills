---
name: clan-core
description: "Fleet management with clan-core: inventory (machines/instances/roles/tags), clanServices (roles, perInstance/perMachine, darwin), the experimental exports system, the clan CLI, vars secrets (sops/age backends), data-mesher integration (mesh file sync, dm-dns, pki, pull-deploy), networking/deployment model, VM testing, and clan-core's own contributing/style guides. Load when working on anything clan.* or consuming inputs.clan-core."
---

# clan-core

[Clan](https://docs.clan.lol) is a toolset for managing a fleet of NixOS (and
nix-darwin) machines declaratively from one flake. `clan-core` is the flake
input that provides that toolset: a flake-parts module (the `clan` option),
the `clan` CLI, a library of prebuilt clanServices, the vars secrets system,
and `clanLib`. Load this skill when a flake has a `clan-core` input.

Worked examples are from the home repo (`andrewthomaslee/home`) and the fleet
repo (`andrewthomaslee/borg`) — the patterns are generic; substitute your
repo's names.

Researched against clan-core `main` post-26.05 (commit `8b9fd720b`,
VERSION `unstable`; latest stable branch `26.05`). Where a feature is flagged
*experimental*, upstream explicitly reserves the right to change it without
migration.

## Where the docs are

The docs site is always built from `main` (unstable); stable releases get
versioned URL prefixes. Prefer `26.05` links for stable behavior and
`unstable` for main-only features — check `docs/src/releases/next.md` in the
clan-core checkout for what is about to change.

| Topic | URL |
|---|---|
| Docs home | https://docs.clan.lol · https://clan.lol/docs/26.05 |
| 26.05 release notes | https://clan.lol/docs/26.05/releases/26-05 |
| Next release notes (main) | https://clan.lol/docs/unstable/releases/next |
| Inventory intro | https://clan.lol/docs/26.05/guides/inventory/intro-to-inventory |
| Autoincludes | https://clan.lol/docs/26.05/guides/inventory/autoincludes |
| Using clanServices | https://clan.lol/docs/26.05/guides/services/intro-to-services-revised |
| Authoring a clanService | https://clan.lol/docs/26.05/guides/services/community |
| Service author reference (`clan_service` options) | https://clan.lol/docs/26.05/reference/options/clan_service |
| Exports guide | https://clan.lol/docs/26.05/guides/services/exports |
| Vars intro | https://clan.lol/docs/26.05/guides/vars/intro-to-vars |
| Vars concepts | https://clan.lol/docs/26.05/guides/vars/vars-concepts |
| Custom generators | https://clan.lol/docs/26.05/guides/vars/vars-custom-generators |
| age backend | https://clan.lol/docs/26.05/guides/vars/age/age-backend |
| sops internals | https://clan.lol/docs/26.05/guides/vars/sops/secrets |
| Vars troubleshooting | https://clan.lol/docs/26.05/guides/vars/vars-troubleshooting |
| Networking guide | https://clan.lol/docs/26.05/guides/networking/networking |
| flake-parts guide | https://clan.lol/docs/26.05/guides/flake-parts |
| CLI reference | https://clan.lol/docs/26.05/reference/cli |
| `clan` (flake) options | https://clan.lol/docs/26.05/reference/options/clan |
| `clan.core` (machine) options | https://clan.lol/docs/26.05/reference/clan.core |
| ADRs | https://clan.lol/docs/26.05/decisions |
| Source / issues / PRs (Gitea) | https://git.clan.lol/clan/clan-core |
| Community services | https://git.clan.lol/clan/clan-community |

In a clan-core checkout the same content is at `docs/src/` (guides,
reference, releases, decisions), and the CLI reference is generated from
`pkgs/clan-cli` (`clan_cli/cli.py` is the command registry —
`register_parser` functions per subcommand). Options reference pages are
generated from the Nix modules, so the module source is the ground truth:
`flakeModules/clan.nix` (flake option), `modules/clan/` (inventory, vars,
templates), `modules/inventoryClass/` (inventory schema),
`lib/inventory/distributed-service/` (service evaluation),
`nixosModules/clanCore/` (`clan.core.*` machine options).

## What it adds to a flake

Plain `nixosConfigurations` already cover per-machine config. clan-core adds
the fleet layer on top:

- **Machine registry** — one `inventory` lists every machine, its SSH deploy
  target, and tags. Adding a machine is adding an entry, not a wiring change.
- **Tag-driven config** — services and config attach to tags
  (`pc`, `server`, `dev`, ...), not to machine names. A new machine with the
  right tags automatically gets the right config.
- **Cross-machine services** — clanServices are reusable units with roles
  and multi-instance support, resolved from the inventory. Since 25.11 they
  can target nix-darwin as well (`darwinModule` alongside `nixosModule`).
- **Build-time exports** — services publish facts (node addresses,
  interfaces, MTUs, endpoints) that other services consume during
  evaluation, not at deploy — see
  [Exports](#exports-and-the-strict-eval-check). Still experimental.
- **Secrets lifecycle** — vars generate, encrypt, store, and deploy secrets
  — see [clan vars](#clan-vars).
- **Operational tooling** — `clan machines update|install|create|ssh`, `clan
  vars`, `clan secrets`, `clan select`, `clan flash`, `clan backups`,
  `clan init`.

Clan follows a "clan as library" design ([ADR
02](https://clan.lol/docs/26.05/decisions/02-clan-as-library)): every piece
is importable on its own. It composes with flake-parts via flakeModules, so
the flake's other outputs (packages, devShells, checks) are unaffected.
Machines are evaluated statically from the inventory — clan never contacts a
machine to evaluate.

`machineClass` defaults to `"nixos"`; set `"darwin"` explicitly for Macs
(there is no auto-detection: NixOS and nix-darwin module systems differ).
`x86_64-darwin` was dropped in 26.05; only Apple-silicon darwin remains.

## How it works with flake-parts

```nix
# flake.nix
inputs = {
  # 26.05 archive (or /archive/main.tar.gz for unstable)
  clan-core.url = "https://git.clan.lol/clan/clan-core/archive/26.05.tar.gz";

  # one nixpkgs instance serves the whole graph. Following
  # clan-core/nixpkgs tracks the nixpkgs clan's own CI tests against;
  # following your own nixpkgs instead means you control the pin but
  # drop ahead of clan's testing. Pick one and stay consistent.
  nixpkgs.follows = "clan-core/nixpkgs";

  # clan-core is a flake-parts flake: reuse its instance instead of
  # carrying a second flake-parts.
  flake-parts.follows = "clan-core/flake-parts";
};
```

Community flake inputs must follow the same clan-core instance:
`inputs.clan-core.follows = "clan-core"` on the community input (the home
repo does this for `clan-community`).

```nix
# outputs — import the flake module, then configure under the `clan` option
{
  imports = [inputs.clan-core.flakeModules.default];
  clan = {
    meta.name = "my-clan";
    meta.domain = "my-clan.lol";
    # everything else: inventory, machines, modules, vars.settings, ...
  };
}
```

The `clan` option (a submodule of class `"clan"`, defined in
`modules/clan/top-level-interface.nix`) accepts, among others:

- `meta` — `name`, `domain` (both required, unique across the clans you
  manage), `description`, `icon`.
- `inventory` — the fleet: `machines`, `instances`, `tags` (see below).
- `machines.<name>` — per-machine NixOS/nix-darwin config modules (merged
  with the autoincluded `machines/<name>/` files).
- `modules` — registry of clanServices by scoped name
  (`"@org/name"`). Consumed via `inventory.instances.<i>.module.name`.
- `specialArgs` — extra args passed to every machine module system.
- `vars.settings` — clan-wide vars backend selection and options
  (`secretStore`, `recipients`, `age.externalStore`) — see [vars](#clan-vars).
- `templates` — clan templates (`clan templates`).
- `checks` — assertions that abort evaluation with a message when false.
- `deprecatedModules` — names of `modules` entries that are migration stubs
  for removed services: registered so inventory references produce a helpful
  error, skipped by docs/schema/CLI service listings.
- `pkgsForSystem` / `perSystem.<system>.clan.pkgs` — one global package set
  for all machines (performance; `nixpkgs.*` options ignored when set).
- `exportInterfaces` — **internal/hidden in current main**; the exports
  interfaces are now centrally defined in clan-core (see
  [Exports](#exports-and-the-strict-eval-check)).
- Outputs produced for you: `nixosConfigurations`, `darwinConfigurations`,
  `nixosModules."clan-machine-<name>"`, `darwinModules."clan-machine-<name>"`,
  and the internal-but-stable `clanInternals` interface the CLI evaluates.

The home repo keeps the tree modular instead of one inline `clan` block:

```nix
# flake-parts/default.nix
clan = {
  inventory = import (relativeToRoot "inventory.nix") {inherit customLib;};
  specialArgs = {inherit customLib inputs self;};
  # inherit exportInterfaces from a community service flake-module
  inherit ((import "${inputs.clan-community}/services/rancher/flake-module.nix" {}).clan) exportInterfaces;
};
```

and registers its services from `clanServices/*/flake-module.nix` files
(each `clan.modules."@andrewthomaslee/<name>" = ./default.nix;`, collected by
`clanServices/flake-module.nix`) — either way they land in `flake.clan.modules`.

## How clan evaluates a flake

- **Autoincludes** — every directory under `machines/<name>/` is
  auto-registered as a machine; `configuration.nix`,
  `hardware-configuration.nix`, `facter.json`, and `disko.nix` inside are
  imported automatically. Machine dirs need no import list.
- **`.clan-flake`** — sentinel file marking the repo root for the CLI and
  clan's Nix evaluation; falls back to `.git`, `.hg`, `.svn`, or `flake.nix`.
  `CLAN_DIR` must point at this root for the CLI (the home repo's devShell
  shellHook sets it via varlock).
- **`inventory.json`** — clan-managed install metadata at the repo root,
  merged into the inventory (currently carries `machines.<name>.installedAt`
  timestamps). Generated by clan tooling — never hand-edit (same class as
  `flake.lock`).
- **Git tree only** — clan evaluates machine configs and services from the
  git tree (`builtins.filterSource`-style restricted eval); untracked files
  are invisible. `git add` new files before evaluating.
- **Evaluation entry points** — machines are built by
  `nixpkgs.lib.nixosSystem` / `nix-darwin.lib.darwinSystem` with
  `modules = [ (config.outputs.moduleForMachine.<name> or { }) ]` plus
  `specialArgs = { inherit clan-core; } // config.specialArgs`. If
  specialArgs are not threaded through, machine evals die with
  `attribute '<arg>' missing` (the home repo passes its `customLib` there;
  see the circularity exception in the `lib`/`nix-style` skills).

## The inventory

`inventory.nix` is the machine source of truth. Two-part mental model:

```nix
inventory = {
  machines = { ... };   # what exists
  instances = { ... };  # what runs on it
};
```

Upstream examples put everything in a `clan.nix` file; the option is
`clan.inventory`, so a repo may split it into its own `inventory.nix`
(dendritic style — the home repo does) or inline it.

### machines

```nix
inventory.machines = {
  nixos = {
    deploy.targetHost = "root@nixos";   # SSH address for clan deploy tooling
    tags = ["pc" "intel" "lan" "dev"];
  };
};
```

Per-machine options (`modules/inventoryClass/inventory.nix`):

- `deploy.targetHost` — SSH address (`user@host:port?SSHOption=value&...`),
  default null (local deploys only). Also settable per machine module as
  `clan.core.networking.targetHost`.
- `deploy.buildHost` — remote builder for `nixos-rebuild`; null = build on
  the target.
- `deploy.forwardAgent` — per-machine SSH agent forwarding override; null
  inherits `clan.core.networking.forwardAgent` (default **false** since the
  25.11→26.05 cycle — enabling it globally is a security decision).
- `machineClass` — `"nixos"` (default) or `"darwin"`.
- `installedAt` — unix timestamp set by the installer (lives in
  `inventory.json`).
- `tags` — membership labels, plus `name` / `description` / `icon` meta.

**Tags.** Clan provides built-in tags `all`, `nixos`, and `darwin` (by
`machineClass`); every other tag exists because machines list it.
`inventory.tags` can additionally define tags statically
(`inventory.tags.foo = ["machineA" "machineB"]`) or dynamically as a
function of the machines — with a recursion warning: never compute tags
from `machine.tags`. The home repo uses plain per-machine `tags`.

### instances

An instance puts a service to work: it names the service module and says
which machines fill which roles:

```nix
inventory.instances = {
  # one user account per person — same service, twice, via module.name
  netsa = {
    module.name = "users";
    module.input = "self";        # optional: which flake input provides it
    roles.default = {
      settings = {
        user = "netsa";
        share = true;
      };
      tags = ["netsa"];            # machines by tag ...
      extraModules = [(relativeToRoot "users/netsa")];
    };
  };
};
```

- **Roles** — each service defines its roles (`default` for uniform
  services, named roles like `client`/`server` for asymmetric ones). Assign
  machines by tag (`roles.<role>.tags = [...]`) or by name
  (`roles.<role>.machines."<name>" = {}`); both may be mixed and are unioned.
- **Settings** — `roles.<role>.settings` applies role-wide; per-machine
  `roles.<role>.machines.<name>.settings` merge on top. `= {}` means
  "include, nothing extra".
- **`module.name`** — the service module the instance uses. Defaults to the
  instance's attribute name; set it to reuse one service in several
  instances (e.g. `user-sally` and `user-fred`, both `module.name =
  "users"`). Not every service supports multi-instance — check its docs.
- **`module.input`** — flake input providing the module: `"self"` for
  repo-local services, an input name for community flakes; unset/null means
  clan-core's own library (`users`, `sshd`, `wifi`, `borgbackup`, ...).

## clanServices

clanServices are clan's service model (the successor to `clanModules` —
see the migration guide). A service is a module with `_class =
"clan.service"`, declaring a manifest, roles, and the NixOS/darwin config
each role applies. **Authoring or editing a service (argument contracts,
manifest fields, multi-instance namespacing, exports writes, vars inside
services, testing, upstreaming): load the `clanservices` skill** — this
section is the operator view: what services are, how they get registered,
and how to consume them from the inventory.

```nix
# clanServices/machine-type/default.nix (shape only — the clanservices skill has the full contract)
{
  _class = "clan.service";
  manifest = {
    name = "machine-type";
    description = "Machine classification/profiles";
    readme = "...";              # or builtins.readFile ./README.md
    categories = ["..."];
    maintainers = ["..."];      # since 25.11
    exports.out = ["peer"];     # only if the service exports (see Exports)
  };

  roles = {
    pc = {
      interface = {lib, ...}: {          # role-wide settings options
        options.someSetting = lib.mkOption {type = lib.types.str;};
      };
      perInstance = {
        instanceName,
        settings,
        machine,
        roles,
        meta,
        ...
      }: {
        nixosModule = ./pc.nix;          # config for machines in role pc
        # darwinModule = ./pc-darwin.nix;  # since 25.11
      };
      description = "Personal Computer";
    };
  };

  # common configuration for every machine of every instance
  perMachine = {instances, machine, meta, ...}: {
    nixosModule = {self, inputs, lib, pkgs, ...}: {
      imports = [self.nixosModules.default];
    };
  };
}
```

Key facts for using services (authoring depth lives in the `clanservices`
skill):

- **Roles** — each service defines its roles (`default` for uniform
  services, named roles like `client`/`server` for asymmetric ones);
  instances assign machines to roles by tag or name, with role-wide and
  per-machine settings that merge on top.
- **`roles.<role>.interface`** — the machine-agnostic option declarations
  that `roles.<role>.settings` in the inventory targets. `perInstance` runs
  per (instance × machine of that role) and returns the `nixosModule` /
  `darwinModule` (25.11+) applied to that machine; inside it, normal
  NixOS-module rules apply (import repo modules, declare vars generators).
- **Registration** — the service lives at a repo path and is registered in
  `flake.clan.modules` under a scoped name: home repo convention
  `@andrewthomaslee/<name>` (each `clanServices/<name>/flake-module.nix`),
  upstream core services bare names, community unprefixed. Inventory
  instances then set `module.name` / `module.input = "self"`.

`clanServices/` sits at the repo root, **not** under `flake-parts/` —
import-tree loads `flake-parts/*.nix` as flake-parts modules, while clan
imports clanServices from the paths registered in `flake.clan.modules`.
Mixing them up double-loads or mis-classifies modules.

### The tag-service pattern

The home repo attaches config to tags with one clanService whose roles are
the tags themselves:

```nix
# clanServices/tags/default.nix
{
  _class = "clan.service";
  manifest.name = "tags";
  roles = {
    dev   = {perInstance.nixosModule = ./dev.nix; description = "Dev Computer";};
    intel = {perInstance.nixosModule = ./intel.nix;};
    lan   = {perInstance.nixosModule = ./lan.nix;};
    wan   = {perInstance.nixosModule = ./wan.nix;};
  };
}
```

```nix
# inventory.nix — each role is offered to machines carrying that tag
tags = {
  module.input = "self";
  module.name = "@andrewthomaslee/tags";
  roles = {
    dev.tags.dev = {};
    intel.tags.intel = {};
    lan.tags.lan = {};
    wan.tags.wan = {};
  };
};
```

`lan.nix` just sets `hostSpec.networking.lan.enabled = true`. The payoff:
tagging a machine in the inventory (`tags = ["lan" "dev"]`) pulls in all its
config — no service edit, no machine edit beyond the tags.

### Core services (26.05)

`admin` (deprecated), `borgbackup`, `certificates`, `data-mesher`,
`dm-dns` *(new)*, `dyndns`, `emergency-access`, `garage`, `hello-world`,
`importer`, `installer` *(new, experimental — turn a machine into an
install image)*, `internet`, `kde`, `localbackup`, `matrix-synapse`,
`monitoring` (new client/server roles; telegraf removed), `mycelium`,
`ncps` *(new — nix binary cache proxy)*, `p2p-ssh-iroh` *(new; stable on
main)*, `packages`, `pki` *(new — static certificates)*, `sshd`, `syncthing`,
`tor`, `trusted-nix-caches`, `users`, `wifi`, `wireguard`, `yggdrasil`,
`zerotier` (reworked for multi-instance; `clan.core.networking.zerotier.*`
removed). `coredns` moved to clan-community.

### Community services

Community flakes (e.g. [clan-community](https://git.clan.lol/clan/clan-community))
add more; they must follow the repo's clan-core input. The home repo imports
a community service's interface directly:

```nix
# inherit exportInterfaces from a community service flake-module
inherit
  ((import "${inputs.clan-community}/services/rancher/flake-module.nix" {}).clan)
  exportInterfaces
  ;
```

## Exports and the strict-eval check

ClanServices exchange facts **at build time** through exports *(still
experimental as of 26.05+)*: a service publishes values (node IPs,
interface names, MTUs, endpoints, auth material) and consumer services
select them during evaluation instead of hardcoding addresses in settings.

### Publishing

A service declares which export interfaces it may emit in
`manifest.exports.out`, then publishes values with `mkExports` (available
in the args of `perInstance` and `perMachine`); instance-/service-scoped
facts go in a top-level `exports` attribute keyed with
`clanLib.buildScopeKey`. `mkExports` scopes every key under the emitting
context (`service:instance:role:machine`) and scope ownership is enforced
at eval (a service writes only its own service scope; `perInstance` only
its instance scope; `perMachine` only its machine scope; an unregistered
interface name in `manifest.exports.out` throws with the available ones).
The full write-side pattern — with the borg repo's `lan` service as the
worked example — lives in the `clanservices` skill (§10).

### Built-in export interfaces

Since the 25.11→26.05 refactor the interfaces are centrally defined in
clan-core (`modules/clan/export-modules/`), and the built-in set is:

| Interface | Emits |
|---|---|
| `peer` | SSH-reachable hosts (`hosts` list of plain strings or var references), `name`, `port`, `user`, `SSHOptions` |
| `networking` | `interface`, `mtu`, `priority`, IP addresses |
| `endpoints` | service endpoints (new in 26.05) |
| `auth` | credentials/identity (new in 26.05) |
| `generators` | var-generator references (new in 26.05) |
| `dataMesher` | data-mesher overlay facts (new in 26.05) |

Custom interfaces were registered via `clan.exportInterfaces.<name>`; that
option is now **internal/hidden** in main (still settable — the home repo
inherits a community one — but treat it as experimental surface).

### Consuming

Consumers receive the whole exports tree and select with `clanLib` helpers.
Export keys are `service:instance:role:machine` scope strings; never touch
the raw keys — always go through `clanLib`:

- `clanLib.parseScope "svc:inst:role:machine"` →
  `{serviceName, instanceName, roleName, machineName}`.
- `clanLib.buildScopeKey {serviceName = "..."; ...}` → scope string (empty
  parts = `""` = wildcard level).
- `clanLib.selectExports (scope: scope.serviceName == "lan") exports` —
  predicate over the parsed scope; returns the matching subset keyed by
  scope string.
- `clanLib.getExport {serviceName = "lan"; machineName = "...";} exports` —
  one scope; throws with the full scope breakdown and available exports if
  missing.

```nix
# a consumer reading the borg repo's lan exports (condensed)
{
  exports,
  machine,
  ...
}: let
  # every machine's peer hosts in the named lan instance
  lanPeers = clanLib.selectExports
    (scope: scope.serviceName == "lan" && scope.instanceName == settings.network)
    exports;

  # one machine's netif export
  myNetif = clanLib.getExport {
    serviceName = "lan";
    instanceName = settings.network;
    machineName = machine.name;
  } exports;
in {
  # ...
}
```

**Every export-interface option needs a `default` — or every exporter must
set it.** An option left undefined passes every other static gate
(formatter, lint, machine evals, VM tests) and only explodes when the clan
CLI deep-evaluates the exports tree during `clan machines install/update`
(via `clan select 'clan.?exports'`): "accessed but has no value defined",
mid bring-up, on the operator box. This exact failure motivated the check
below.

### The strict-eval check

Force the same deep evaluation inside `nix flake check` so an undefined
export leaf surfaces as a red check instead of a deploy-time failure:

```nix
# flake-parts/checks.nix — pattern from andrewthomaslee/borg
{
  self,
  ...
}: {
  perSystem = {pkgs, ...}: {
    checks.clan-exports-strict-eval = pkgs.runCommand "clan-exports-strict-eval" {
      # exportsJson forces every export leaf at *eval* time: checks are
      # evaluated (not built) by `nix flake check`, so a throw in the
      # toJSON fails the check — the same deep eval `clan machines
      # install/update` performs via `clan select 'clan.?exports'`.
      exportsJson = builtins.toJSON self.clan.exports;
    } "touch $out";
  };
}
```

Add the check once any service sets `manifest.exports.out` — with no
exports, `self.clan.exports` is empty and the check passes trivially.
Serialize only `clan.exports`; do not `--json` the interfaces (see
Gotchas).

## data-mesher

data-mesher is clan's mesh file-distribution daemon — the runtime plumbing
under the experimental distributed-services stack (dm-dns, pki, and
clan-community's dm-pull-deploy / dm-wireguard-star). It is a separate
project: https://git.clan.lol/clan/data-mesher (Go; **experimental** — the
README states upstream is exploring a new architecture; v0.1.0 was the old
CRDT-based design).

### What it is

A daemon for distributing **cryptographically signed files** across a
mesh network where peers gossip directly (libp2p/memberlist cluster,
default port 7946; local HTTP API on 7331):

- **Files** are identified by name (regex `^[a-z0-9_]{1,255}(/[a-z0-9_]{1,255})*$`)
  and must be signed by an authorized ED25519 key.
- **No central server** — every peer independently verifies signatures.
- **Self-healing** — files propagate via periodic push/pull with random
  peers; conflict resolution by signature timestamp (newer wins).
- **Tombstones** — deletion is a signed delete record that gossips.
- **Per-file TTL** (ADR-0009) — the author can commit a `ValidFor` duration
  into the signed metadata; every node independently reaps the file once
  `SignedAt + ValidFor` passes (no tombstone needed; tolerant of clock
  skew). This powers heartbeat-style announcements.
- **Static allowlists** — `dm.toml [files]` maps file name → list of
  base64 ED25519 signer pubkeys; only listed, validly signed files sync.
- **Signed namespaces** (ADR-0008) — a file path `{namespace}/{url-encoded
  signer pubkey}` is authorized automatically when the signer holds a
  certificate signed by the network key. Lets nodes publish under their own
  namespace without per-file config.

Upload flow: the client signs `content + filename + timestamp (+TTL)` and
POSTs to any node's HTTP API; the node verifies against the allowed
signers and gossips the signature; peers fetch, verify, and store locally.

CLI (package `data-mesher`):

```bash
data-mesher generate keypair|network|identity-key|signing-key
data-mesher peer id <identity.pub>            # derive libp2p peer ID
data-mesher certificate sign|verify           # network-key-signed node certs
data-mesher file update <path> --url http://localhost:7331 --key <priv> --name <file>
data-mesher file delete ...
data-mesher server
```

NixOS module (from the data-mesher flake,
`inputs.data-mesher.nixosModules.default`):
`services.data-mesher.{enable, package, user, group, openFirewall,
pluginDirectories, settings}` — `settings` is freeform TOML rendered to
`dm.toml` (`log_level`, `state_dir`, `cluster.{port,bootstrap_peers,push_pull_interval,interfaces}`, `http.{port,interface}`,
`network.{id,files,namespaces}`, identity key/cert paths).

data-mesher's own docs live in its repo: `docs/site/` (mkdocs) and the
ADRs in `docs/site/decisions/` — ADR-0002/0007 (CRDT → files),
ADR-0008 (signed namespaces), ADR-0009 (per-file TTL) tell you why it
looks the way it does. Key source: `pkg/model` (signature, name rules),
`pkg/state` (file/signature store, TTL sweeper), `pkg/crypto`
(keypairs, certificates), `cmd/` (CLI).

### The `dataMesher` export interface

clan-core centrally defines the interface
(`modules/clan/export-modules/data-mesher.nix`) that services use to
declare what the mesh should carry:

- `dataMesher.files` — attrsOf (listOf str): file name → base64 ED25519
  signer pubkeys. Merged across **all** exports in the clan, so any service
  can add its file to the mesh's allowlist.
- `dataMesher.namespaces` — listOf str: authorized signed namespaces,
  likewise merged fleet-wide.

### The `data-mesher` clanService

`clanServices/data-mesher` (experimental) wires the daemon into the
inventory. Roles: `default` (mesh node) and `bootstrap` (initial gateway).
The v1 `admin`/`peer`/`signer` roles are removed — assigning them fails
the eval with a migration message. Per instance:

- **vars generators** (this is the integration masterpiece — study it):
  - `data-mesher-network` — `share = true`; an ED25519 **network keypair**:
    the mesh's root of trust. `network.key` has `deploy = false` (signing
    input only); `network.pub` is public and **is the network ID** every
    file is signed for.
  - `data-mesher-node-identity` — `dependencies = ["data-mesher-network"]`;
    per-machine identity keypair, `peer.id` (libp2p ID from the pubkey),
    and an **identity certificate** signed by the network key
    (`data-mesher certificate sign --validity ${settings.certificateValidity}`,
    default `2160h`/90 days — regenerate before expiry). Secret files are
    owned by the daemon's user/group.
- **bootstrap peers** — machines in `roles.bootstrap.machines` are turned
  into libp2p multiaddrs via `clanLib.getPublicValue` of each machine's
  `peer.id`: `/dns/<name>.<domain>/tcp/<port>/p2p/<peerID>`, merged with
  `roles.default.settings.extraBootstrapPeers`. Assertion: at least one
  bootstrap peer must exist.
- **file authorization** — the service folds every `dataMesher.*` export in
  the clan together with role settings `network.files` /
  `network.namespaces` and writes them into `dm.toml`, so cooperating
  services (dm-dns below) get their files synced without any config here.
- Settings: `logLevel`, `port` (7946), `certificateValidity`, `interfaces`,
  `network.files`, `network.namespaces`, `extraBootstrapPeers`. HTTP is
  bound to `lo:7331` (loopback-only API; push from the machine itself).

### The `dm-dns` clanService — distributed internal DNS

`clanServices/dm-dns` (experimental) gives every machine fleet-internal
name resolution for `<endpoint>.<clan domain>`:

- `manifest.exports.inputs = ["endpoints"]` — it **consumes** the
  `endpoints` export (each service publishes `endpoints.hosts` for its
  public names); every internal host becomes a CNAME to
  `<machine>.<domain>`.
- Role `push` — holds the shared `dm-dns-signing-key` vars generator
  (data-mesher signing keypair) and **exports**
  `dataMesher.files."dns/cnames" = [ signing.pub ]`, authorizing its zone
  file on the mesh. Ships a `dm-send-dns` helper that signs and uploads
  `dns/cnames` to the local data-mesher.
- Role `default` — every machine: generates the shared `dm-dns` zone file
  (public var; `validation.zoneContent` forces regeneration when exports
  change), runs **unbound** on `127.0.0.1:5353` including
  `/var/lib/data-mesher/files/<network>/dns/*` (the mesh-delivered zone),
  with a `systemd.path` watching that directory to reload unbound on
  updates; **systemd-resolved** routes `~<domain>` queries to unbound. Also
  pins nginx/caddy virtual hosts of internal endpoints to
  `clan.core.networking.internalListenAddresses`.
- Requires the `data-mesher` service on all machines and at least one
  `push` machine; combine with the `pki` service for TLS on the internal
  names. Ordering: generate vars (`clan vars generate`) before deploys,
  then run `dm-send-dns` on a push machine whenever endpoints change.

### The `pki` clanService

`clanServices/pki` (new in 26.05, stable) — internal TLS for clan
endpoints. Also `manifest.exports.inputs = ["endpoints"]`; derives the
machine's internal endpoint names from exports and generates per-endpoint
cert/key vars generators (`cert-<endpoint>`), wiring caddy/nginx TLS
directives. Together `dm-dns + pki` make `https://<service>.<domain>` work
fleet-wide.

### clan-community services built on data-mesher

- **`dm-pull-deploy`** — pull-based NixOS deployment through the mesh:
  `push`-role machines distribute a flake reference as a signed
  data-mesher file (`dm-send-deploy github:org/repo/<rev>`); `default`-role
  machines watch the file and auto-`nixos-rebuild`, reporting their
  deployed revision back for rollout tracking. An alternative to the
  FlakeHub/`fh apply` pull model that works without any central registry.
- **`dm-wireguard-star`** — WireGuard star topology with dynamic peers:
  the controller publishes a static (signing-key-authorized) file; peers
  announce themselves via **signed namespaces** and re-publish every 2
  minutes with a 10-minute TTL, so dead peers are reaped by the TTL
  sweeper and removed from the controller's `wg syncconf` config — no
  rebuilds to add/remove peers.

### Use cases and when to reach for it

- **Fleet-internal service discovery**: services export `endpoints.hosts`;
  dm-dns + unbound make names resolve on every machine; pki adds TLS.
  This is the modern replacement for hand-maintained `networking.hosts`.
- **Distributing small signed blobs** cluster-wide: configs, join tokens,
  zone files, deployment targets — anything where per-file signer
  allowlists (or cert-derived namespaces) are the right authorization
  model and eventual consistency is acceptable.
- **Dynamic membership / heartbeats**: TTL-signed files + namespace
  authorization give nodes a self-cleaning way to announce themselves
  (dm-wireguard-star pattern).
- **Air-gapped / registry-less pull deploys**: dm-pull-deploy.
- Not for: large files (gossip bandwidth), strongly consistent state, or
  secrets — use clan vars for secrets; data-mesher files are
  world-readable in `/var/lib/data-mesher` once synced (signature
  integrity, not confidentiality — pair with vars when content must stay
  secret).

The home repo does not run data-mesher yet; the natural fit is internal
DNS/TLS for services on the lan/wan machines (replacing hand-maintained
host entries) once the experimental label is acceptable.

## Networking and how machines get updated

### Reachability: networking services

Clan learns how to reach a machine through **networking services** —
configure several and the CLI tries them in priority order until one
connects (direct SSH fails → VPN → Tor fallback):

| Service | Priority | What |
|---|---|---|
| `p2p-ssh-iroh` | 3000 | NAT-traversing SSH over Iroh QUIC (experimental in 26.05, stable on main) |
| `internet` | 2000 | direct SSH via `settings.host` (+ `settings.port`, `settings.user` since 25.11) |
| `wireguard` | 1000 | WireGuard mesh, auto IPv6 |
| `zerotier` | 900 | ZeroTier mesh |
| `mycelium` | 800 | Mycelium overlay |
| `tor` | 10 | onion services, last resort |

`deploy.targetHost` in the inventory remains the plain-SSH baseline. SSH
agent forwarding (`clan.core.networking.forwardAgent` /
`inventory.machines.<name>.deploy.forwardAgent`) defaults to **off**; enable
per machine only when the build host needs your agent for private repos,
and consider deploy keys or token HTTPS instead.

### Deployment styles

Two styles are available; inventory, tags, and vars stay the source of
truth either way:

- **Pull-based (the home repo's style)** — CI publishes a release to
  FlakeHub; machines run the `apply-*` packages (`apply-now home`,
  `apply-and-reboot home` for a clean remote reboot). `fh apply` mechanics:
  the `determinate` skill. CI never SSH-pushes.
- **Push-based (`clan machines update <machine>`)** — direct SSH deploy
  from the operator box. 26.05 made updates safer: the new generation is
  registered in the bootloader **before** live activation, so a failed
  activation still leaves a bootable system (reboot to apply). Use
  `--no-check` to force past switch inhibitors, `--specialisation <name>`
  to activate a NixOS specialisation instead of the default.

`clan.core.deployment.requireExplicitUpdate = true;` (set in
`flake-parts/nixosModules/clan.nix` in the home repo) excludes a machine
from `clan machines update` **with no machine argument** — so a stray
"update everything" fails to touch pull-deployed machines. A targeted
`clan machines update <machine>` still works.

`clan machines install <machine>` stays the first-time path: partitions
(disko), installs, bootstraps vars; after that, updates flow through the
chosen style.

## The clan CLI

The CLI is the fleet's control plane. It needs `CLAN_DIR` pointing at the
repo root and the flake in the git tree. It talks to the flake through the
stable Nix interface `flake.clanInternals` (hidden option, "stable nix
interface interacted by the clan cli") — that is also the seam for
debugging (`nix show-config`-style evaluation of what the CLI sees).

Top-level commands (registry in `pkgs/clan-cli/clan_cli/cli.py`):

| Command | What it does |
|---|---|
| `clan init <name>` | scaffold a new clan (replaces the removed `clan flakes create`; interactive; new clans get the age backend, `p2p-ssh-iroh`, sshd/users/inventory instances) |
| `clan machines list / create / delete` | machine registry ops (`machines create <name> --tags ... --target-address ...`) |
| `clan machines update <machine>` | SSH deploy (bootloader-registered, `--no-check`, `--specialisation`) |
| `clan machines install <machine>` | first-time install (disko + vars bootstrap) |
| `clan machines build` | build a machine closure (`--no-secrets`, `--no-sandbox`, `--system` since 26.05; `vm` format removed) |
| `clan machines hardware` | gather `facter.json` reports |
| `clan machines generations` | list generations (up-to-date check removed on main) |
| `clan ssh <machine>` | SSH to a machine through the networking-service chain |
| `clan vars ...` | secrets workflow (below) |
| `clan secrets ...` | low-level sops secrets ops (admin users/groups, debugging — prefer vars) |
| `clan select <selector> [--impure]` | evaluate a flake selector, print JSON (e.g. `clan select 'clan.?exports'`) |
| `clan show` / `clan network` | clan meta / network info |
| `clan backups list` | state backups (driven by `clan.core.state`) |
| `clan flash` / `clan templates` / `clan completions` | imaging, clan templates, shell completions |

Removed along the way: `clan vms`, `clan state` (the `clan.core.state`
options remain for backups), the `vm` vars backend.

Scripting notes:

- The CLI prints lines like `warning: unknown setting 'eval-cores'` on
  stdout. Filter any line starting with `warning:` before feeding output to
  a parser. The home repo's `get-keys` app
  (`flake-parts/apps/get-keys.nix`) wraps the CLI in Python with that
  filter to extract machine age keys for provisioning.
- `clan vars get` output is for consoles and provisioning scripts, not for
  pasting into Nix.
- The CLI is available as a package:
  `inputs'.clan-core.packages.clan-cli` (use it in devShell
  `runtimeInputs` or apps).

## clan vars

Vars are clan's secrets and generated-values system. A **generator** is a
named unit that produces one or more **files** — by prompting the operator,
by running a script, or both, possibly consuming other generators as
dependencies. Files marked secret are encrypted at rest in the repo and
decrypted on the target machine at activation; public files (public key
halves, certs metadata) are stored as plain `value` files. Secrets are
never in Nix source, never plaintext in the store, and the encrypted copies
live **in the flake repo** (unless the age external store is used), so a
checkout is self-contained.

### Backends

`clan.vars.settings.secretStore` selects the backend **at clan level**
(`"sops"` default, `"password-store"`, `"age"`, `"custom"`). Setting the
backend per machine (`clan.core.vars.settings.secretStore`) is deprecated
and only consistency-checked.

- **sops** (default): sops + age recipients; integrates with sops-nix on
  machines. Admin identity at `~/.config/sops/age/keys.txt` (or
  `SOPS_AGE_KEY` / `SOPS_AGE_KEY_FILE`).
- **age** *(experimental in 26.05; default for new `clan init` clans on
  main)*: pure age encryption, machine keypairs with key indirection —
  each machine gets an age keypair whose private key is encrypted to your
  admin recipients; secrets are encrypted to the machine public keys. User
  key rotation re-encrypts only machine keys, not every secret. Identity
  discovery: `$AGE_KEY`, `$AGE_KEYFILE`, `~/.config/age/identities`,
  `~/.config/sops/age/keys.txt`, `~/.age/key.txt`. Recipient config
  (experimental): `vars.settings.recipients.default` (fallback) and
  `vars.settings.recipients.hosts.<machine>` (do not combine — host
  entries replace the default). Encrypted store layout: `secrets/age-keys/
  machines/<machine>/{pub,key.age}` + `secrets/clan-vars/...`;
  `clan.core.vars.age.secretLocation` is where the target receives them
  (default `/etc/secret-vars`). `vars.settings.age.externalStore = true` +
  `$CLAN_AGE_STORE_DIR` keeps the store out of a public repo (commits go
  to that dir's git if it is one).
- **password-store**: pass-compatible store; passage (age-based) is the
  default command (`passPackage` option removed — use
  `vars.settings.password-store.passCommand`).
- Removed: `fs`, `vm` (26.05).

Decryption phases (both sops and age, paths differ slightly): `users` →
before user/group creation (`/run/secrets-for-users` on sops,
`/run/user-secrets` on age), `partitioning` → before disko,
`activation` → before nixos-rebuild/install, `services` → runtime
(`/run/secrets`). Secrets sit on tmpfs and are re-decrypted each boot.

### Declaring generators

Declared in NixOS module land, anywhere a module evaluates (the home repo
declares them in `flake-parts/nixosModules/*.nix`, next to the config that
consumes them):

```nix
# prompt-only generator: value comes from the operator, stored once
clan.core.vars.generators.tailscale = {
  share = true;                       # one var under vars/shared/
  prompts.auth_key.persist = true;    # keep the answer across regenerations
};

services.tailscale.authKeyFile =
  config.clan.core.vars.generators.tailscale.files.auth_key.path;
```

```nix
# script generator: runs in a sandbox, writes files to $out
clan.core.vars.generators."storagebox-ssh-${cfg.boxUser}" = {
  share = true;
  files.ssh-private-key = {};                 # secret (default)
  files.ssh-public-key.secret = false;        # public var, stored as value
  runtimeInputs = with pkgs; [openssh];
  script = ''
    mkdir -p $out
    ssh-keygen -t ed25519 -f $out/ssh-private-key -N "" -C "${cfg.boxUser}-storagebox"
    mv $out/ssh-private-key.pub $out/ssh-public-key
  '';
};
```

Generator anatomy (`modules/clan/export-modules/generic-generator.nix` +
`nixosModules/clanCore/vars/`):

- `share = true` — store one copy under `vars/shared/` (vars many machines
  consume) instead of per-machine copies; generated once for the first
  machine that needs it.
- `files.<name>` — declared outputs; the script must produce exactly these
  under `$out`. Per file:
  - `secret = true` (default) encrypts; `false` stores plaintext.
  - `owner` (default `"root"`), `group` (`"root"` on NixOS, `"wheel"` on
    darwin), `mode` (`"0400"`, 4-digit octal).
  - `neededFor` — `"services"` (default), `"users"`, `"activation"`,
    `"partitioning"` (see phases above; `owner`/`group` forced root for
    `users`, e.g. `hashedPasswordFile`).
  - `deploy = false` — do not ship to the target; use the file only as an
    input to other generators.
  - `restartUnits` — sops-nix only, NixOS only; throws on darwin. For
    services, upstream recommends systemd `LoadCredential=` instead of
    owner/group tricks for non-root services.
- `prompts.<name>` — ask the operator; available to the script as
  `$prompts/<name>`. `persist = true` stores the answer as a secret file;
  `description`, and (via the display module) prompt display options.
- `dependencies = [ "<generator>" ... ]` — other generators whose outputs
  appear as `$in/<generator>/<file>`; forms a DAG (CA chains, cluster
  tokens).
- `validation = {...}` — attrs (bool/int/str, no lists) that invalidate
  the generated values when changed (hashed into `validationHash`); use to
  force regeneration on config changes.
- `runtimeInputs` / `script` — the computation half. Since 26.05,
  interactive prompts **reuse the previous value by default**; a value
  only changes when you pass `--regenerate` (prevents clearing a secret by
  pressing enter).

Two generators with the same name from different modules must merge —
declare with `config.clan.core.vars.generators = lib.mkMerge (...)` (the
home repo does that in `github-mcp.nix`, where generators are conditionally
created per user).

**Deployment permissions (hard-won, verified against clan-core).** sops-nix
deploys secret files `root:root 0400` under `/run/secrets.d/<gen>/vars/...`,
and every directory in that chain is `root:keys 0710` — so a non-root
service user cannot read (or even traverse to) a secret unless you do both
of:

1. add the service user to the `keys` group (directory traversal), and
2. tag the generator file with `owner`/`group`/`mode` (clan maps these onto
   `sops.secrets`, which chowns the deployed file).

A secret that must be readable by ordinary users (a machine-wide client
identity, a shared TLS bundle) cannot live under `/run/secrets` at all:
override `path` on the clan-mapped `sops.secrets` entry to materialize a
real copy elsewhere (e.g. `/etc/...`), and set a readable `mode` on the
generator file. Two traps: guard the override with
`builtins.pathExists "<dir>/vars/.../<file>/secret"` (clan's own filter —
defining the entry before the var is generated points it at the dummy
sopsFile), and never read `config.sops.secrets` from inside a
`sops.secrets` definition (infinite recursion — the membership check must
not come from the option you are defining). `environment.etc` is not an
alternative: it symlinks the `/run/secrets` target (mode ignored on
symlinks, target unreadable). Reference implementation:
`flake-parts/nixosModules/openshell-gateway.nix` in the home repo.

### Storage layout (sops backend)

Encrypted vars are committed to the flake repo:

```
vars/
├── shared/
│   └── openssh-ca/
│       ├── ssh_host_ed25519_key.pub/value   # public: plaintext
│       └── ssh_host_ed25519_key/secret      # secret: encrypted
└── per-machine/
    └── nixos/
        └── <generator>/
            └── <file>/(secret|value)
```

The `vars/` directory belongs to clan tooling. Never hand-edit an encrypted
`secret` file — create or rotate values through the CLI. (The age backend
adds the `secrets/age-keys` + `secrets/clan-vars` trees described above.)

### Consuming a var

Read generated files through the generator's file options:

```nix
services.tailscale.authKeyFile =
  config.clan.core.vars.generators.tailscale.files.auth_key.path;
```

- `.path` — a store path materialized at build time (throws a helpful
  "Try running 'clan vars generate' first" if the file is missing).
- `.value` — plaintext content, **only for non-secret files** (throws for
  secrets).
- `.exists` — whether a non-secret file exists (throws for secrets — the
  existence of an encrypted file cannot be checked at eval time).
- `clanLib.getPublicValue {generator, machine, file, flake;}` — read a
  public value from the in-repo backend, returning `null` when absent
  (service-side consumption without store paths).

Never copy a var's value into config; always reference `.path` so the
encrypted-in-repo / decrypted-on-target model holds.

### Workflow

```bash
# 1. after adding a service or generator: generate missing vars
clan vars generate <machine>          # prompts; empty input auto-generates

# 2. inspect
clan vars list <machine>              # secrets shown as ********
clan vars get <machine> <generator>/<file>   # decrypt and print one value
clan vars check [machines...]         # verify all vars exist (all machines if none given)
clan vars fix [machines...]           # bulk-regenerate missing/invalid vars

# 3. deploy (or push vars directly)
clan machines update <machine>        # home repo: fh apply instead
clan vars upload <machine>            # push generated vars to a machine

# 4. migrate / rotate
clan vars generate <machine> --generator <name> --regenerate
clan vars export / clan vars import   # decrypted dumps and backend migration
```

- `clan vars generate` is idempotent — existing vars are skipped; rerun
  after adding a generator. Missing vars are also auto-generated as part of
  `clan machines update`.
- `clan vars export` → change `secretStore` → `clan vars import` is the
  documented backend-migration path; delete the unencrypted dump after.

### CI and scripted use

- CI needs the admin age key as `SOPS_AGE_KEY` (sops backend) to decrypt
  vars. This repo exports it via varlock from `.env` in the devShell
  shellHook; on GitHub Actions, store it as a secret and set the env var
  directly. With the age backend, CI gets its own recipient key added to
  `vars.settings.recipients`.
- When a machine key is extracted into CI, mask it
  (`echo "::add-mask::$KEY"` in Actions) so it never lands in logs.
- One-shot provisioning with the sops backend: extract the machine age key
  (`clan secrets get <machine>-age.key`), inject it into a fresh VM
  (e.g. terraform cloud-init writes `/var/lib/sops-nix/key.txt`), and the
  machine decrypts everything on first boot — no manual secrets-upload step.
  See the borg repo docs (`documentation/docs/clan/sops.md`).

### `clan.core` machine options related to vars

`clan.core.vars.generators` (above); `clan.core.vars.settings` (backend,
deprecated at machine level); `clan.core.vars.age.secretLocation`;
`clan.core.vars.enableConsistencyCheck` (on by default when the machine can
see the clan config).

## Other `clan.core.*` options on machines

From `nixosModules/clanCore/`:

- `clan.core.settings` — read-only view of the clan: `directory`, `name`,
  `domain`, `tld`, `icon`, `machine.{name,icon,description}`. In tests,
  import `inputs.clan-core.nixosModules.clanCore` and set
  `clan.core.settings = {directory = self; machine.name = "<test>";}` so
  vars-to-sops wiring evaluates.
- `clan.core.networking` — `targetHost`, `buildHost` (both also settable
  from the inventory `deploy.*`), `forwardAgent`,
  `internalListenAddresses`, `extraHosts` (darwin /etc/hosts via launchd).
- `clan.core.deployment.requireExplicitUpdate` — see
  [Deployment styles](#deployment-styles).
- `clan.core.state.<name>` — state folders for `clan backups`
  (`folders`, `preBackupScript`, `postRestoreScript`, ...).
- `clan.core.image.*` — installer images (ISO/...), e.g. the `installer`
  service and `clan.core.image.iso.addFilesScript` (26.05).
- `clan.core.clanPkgs` — mostly removed in 26.05 (downstream-only packages
  like `zerotier-members`, `zerotierone` remain).

## Testing clanServices with NixOS VM tests

clanServices are plain NixOS config in the end, so the hermetic VM-test
harness tests them directly. **Authoring eval/VM tests for a service you
are writing (nix-unit, `clan.nixosTests`, `update-vars`, `clanLib.clan`
throwaway clans): the `clanservices` skill, §17.** This section covers
testing the home repo's own modules through its VM-test harness. The test
file imports the repo's
`nixosModules.default` (not the clan machinery) and flips the `hostSpec.*`
options the service's `perInstance`/`perMachine` modules would set — see
the `vm-tests` skill for the full hermeticity rule, size variants, and the
agent loop. The clan-specific additions:

- Import `inputs.clan-core.nixosModules.clanCore` and set minimal
  `clan.core.settings = {directory = self; machine.name = "<test>";}`
  when the module under test reads `clan.core.*` (the opencode test does
  this so vars-to-sops wiring evaluates).
- Give the test machine sshd so clan's sops backend can derive its age key
  from the SSH host key (no provisioned key exists for a non-inventory
  test VM).
- Fake secrets as `/etc` plain files with an option override pointing at
  them (`patFile = "/etc/vm-github-pat"`-style) instead of real clan vars.

Example: `vm-tests/opencode.nix` in the home repo wires
`clan.core.settings` + fake PAT/key files and asserts MCP server configs
and generated files end-to-end inside the VM.

Upstream's own patterns (in a clan-core checkout):

- VM tests live in `checks/<name>/default.nix`, registered in
  `checks/flake-module.nix` via `self.clanLib.test.baseTest ./<name>
  nixosTestArgs`, exported as `checks.x86_64-linux.<name>`.
- Services with vars need generated test vars first:
  `nix run .#checks.x86_64-linux.<name>.update-vars`, then
  `nix run .#checks.x86_64-linux.<name>`. The `clan.directory` option
  decides where vars are written and read.
- Cheaper tiers: NixOS container tests, pytest unit tests under
  `pkgs/clan-cli` (`pytest`), Nix eval tests (`lib/**/test_*.nix`).
- The contributing guide: `docs/src/guides/contributing/testing.md`.

## Contributing to clan-core

From `docs/src/guides/contributing/CONTRIBUTING.md`:

- **Forge**: Gitea at git.clan.lol — fork clan-core there, add upstream
  (`git remote add upstream gitea@git.clan.lol:clan/clan-core.git`), PR
  from branches. CI runs on Gitea and blocks merges until green.
- **Devshell**: per-package `.envrc` — for CLI work `cd pkgs/clan-cli &&
  direnv allow`. The devshell brings `clan`, Python, formatters, and test
  runners. Linux and macOS supported.
- **Pre-commit**: `./scripts/pre-commit` installs a hook running `nix fmt`
  + lint on staged files; `nix fmt` manually otherwise.
- **Docs workflow**: source in `docs/src/`, dev server in `pkgs/clan-site`
  (hot reload); see `writing-documentation.md` for registering pages in
  the navigation.
- **Overriding sibling projects** (data-mesher, nixos-facter,
  nixos-anywhere, disko): clone locally and point the package reference at
  your checkout (any flake ref works — even a PR), e.g. replace
  `["nixos-anywhere"]` in a `nix_shell` call with
  `["<local-src>#nixos-anywhere"]`.
- **Backports**: `scripts/backport-pr 25.11 <commit>...` cherry-picks onto
  `backport/<target>/<sha>`, pushes, opens a `[<target>] ...` PR via `tea`;
  skips commits that never shipped on the release; `-n` for dry-run.
- **Coding standards CI enforces**: new module names kebab-case; vars
  definitions kebab-case where possible; CLI help strings start with a
  capital letter and no trailing period.
- **Testing expectations**: every feature ships with automated tests —
  prefer unit tests over VM tests; VM tests only for high-level
  integration (they are slow and run without network access).

## clan-core documentation style guide

From `docs/src/guides/contributing/styleguide.md` (follow it for docs and
README prose in clan-* repos):

- **Audience**: assume competence, not familiarity — readers know the
  command line but not Clan or Nix concepts. Show, don't tell: minimal
  working example first, explanation second, deeper theory linked not
  inlined.
- **Grammar**: simple direct sentences; imperative mood; address the reader
  as "you"; active voice; present tense ("This creates ...", never "This
  will create ..."); avoid nominalizations ("Select from the list", not
  "Make a selection"); delete filler words (simply/just/easily/basically/
  obviously, "in order to", "allows you to").
- **Procedures**: one instruction per sentence; don't bury limitations at
  the end — lead with them ("This service does not support multiple
  instances.").
- **Terminology**: one term per concept, always ("machine", never rotate
  host/node/device). **machine = Clan identity; device = hardware.**
  Capitalization list: Clan, NixOS, Nix, Flakes, WireGuard, ZeroTier,
  macOS, Linux, Wi-Fi, DHCP, DNS, git, direnv, bootable USB drive.
- **Code examples**: copy-paste from a terminal where the command actually
  ran — never retype from memory; replace secrets with `<YOUR-KEY>`-style
  placeholders; abbreviate keys/IPs (`ssh-ed25519 AAAAC3NzaC…`,
  `192.168.XXX.XXX`); capitalized `$VARIABLES` directly usable in
  copy-paste; no `# elided` / `# omitted` markers — keep examples focused
  with one concept each and minimal comments.
- **Links**: descriptive text, never "click here"; only link directly
  relevant destinations (no generic Wikipedia-style links).
- **UI language**: match UI labels exactly (wording, casing, spacing).
- **Clean-system discipline**: write steps from a fresh VM / new user
  account, not from memory on a warmed-up dev machine.
- **Docs admonition syntax** (their svelte-md renderer):
  `:::admonition[Title]{type=info collapsible open}` ... `:::` with types
  info | important | tip | example | warning | danger.

## Gotchas

- **`git add` before eval** — clan evaluates machine configs and services
  from the git tree; untracked files are invisible to Nix.
- **`inventory.json` is clan-managed** — regenerated by tooling; never
  hand-edit (same class as `flake.lock`, `disko.nix`, `facter.json`).
- **Tags must resolve** — a role assigned by tag matches only machines
  carrying that tag; keep tag sets consistent between `machines` and
  `instances`, or config silently applies to nothing.
- **Export options need a default** — an export-interface option without a
  `default` (unset by some exporter) passes all static gates and only
  throws when the clan CLI deep-evaluates exports during `install/update`;
  gate it with `checks.clan-exports-strict-eval`
  (see [Exports](#exports-and-the-strict-eval-check)).
- **Don't `--json` the interfaces** — `nix eval .#clan.exportInterfaces
  --json` can never pass: clan's `apply` wrap embeds `mkOption` functions
  in the applied value. Evaluate interfaces through clan's submodule wrap
  instead (the borg repo's `clan-export-interfaces-strict-eval` does
  this); serialize only `clan.exports`. Note `clan.exportInterfaces` is
  internal/hidden on main — custom interfaces are experimental surface.
- **Machine-eval arg circularity** — machine modules get args via
  `clan.specialArgs`, but a module's *config value* cannot use them (see
  the `relativeToRoot` exception in the `nix-style`/`lib` skills).
- **`deployment.requireExplicitUpdate`** — the home repo sets it
  (`flake-parts/nixosModules/clan.nix`) so pull-deployed machines are
  excluded from bare `clan machines update` (no args); targeted updates
  still work.
- **Backend selection is clan-level** — `clan.vars.settings.secretStore`;
  machine-level `clan.core.vars.settings.secretStore` is deprecated (the
  machine asserts consistency when it can see the clan config). Everything
  under `clan.core.vars` (recipients, age locations) is experimental and
  may change without migration.
- **`users` service prompts** — on main, `roles.default.settings.prompt`
  defaults to `false` (random passwords are generated); set `prompt =
  true` to keep being asked. Existing generated passwords are unaffected.
- **`sshd` issues host certificates by default** — since 26.05 the CA is
  always set up and `meta.domain` is the cert search domain; on first
  upgrade expect `File 'id_ed25519.pub' of generator 'openssh-ca' does not
  exist` — run `clan vars generate` and redeploy.
- **Switch inhibitors are not failed deploys** — since 26.05 the
  generation is bootloader-registered before activation; when live
  activation is inhibited (e.g. dbus-broker switch), reboot applies it.
  `--no-check` forces through.
- **SSH agent forwarding defaults off** — deployments relying on forwarded
  agents for private git inputs must set `deploy.forwardAgent` (inventory
  per machine or `clan.core.networking.forwardAgent`) or use deploy
  keys/token HTTPS.
- **Never touch secrets state by hand** — manage admin users/groups with
  `clan secrets`, service values with `clan vars`; manual `clan secrets
  set/remove` can break vars integrity.
