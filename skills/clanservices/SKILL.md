---
name: clanservices
description: "Author production-quality clan.service modules (clanServices) in the official clan-core and clan-community style — module skeleton (_class, manifest with categories/readme/constraints/maintainers), roles + JSON-serializable interfaces, perInstance/perMachine argument contracts, multi-instance namespacing, vars generators (files/share/dependencies/validation/getPublicValue), experimental exports (mkExports/selectExports/scope ownership), darwin support, passing self/pkgs (importApply vs wrapper), registration per repo (clan-core, clan-community, home flake), eval + VM testing, and static verification. Load when adding or changing anything under clanServices/ or services/, or when preparing a service for upstreaming."
---

# clanservices — authoring clan.service modules

Deep-research skill for writing clanServices that match the official
`clan-core` and `clan-community` conventions closely enough to upstream.
Scope: authoring only — operating clan (inventory usage, CLI, vars
workflow, deployment, data-mesher) is the `clan-core` skill, and the repo
VM-test harness is the `vm-tests` skill.

Sources of truth (cloned at `~/clan-core`, `~/clan-community`):

- **Module spec** (authoritative option definitions): `~/clan-core/lib/inventory/distributed-service/service-module.nix` — read it before anything exotic.
- **Authoring guide**: `~/clan-core/docs/src/guides/services/community.md`
- **Exports guide**: `~/clan-core/docs/src/guides/services/exports.md`
- **User-facing intro** (mental model for instances/roles/tags/settings): `~/clan-core/docs/src/guides/services/intro-to-services-revised.md`
- **Vars testing**: `~/clan-core/docs/src/guides/contributing/testing.md` ("Testing services with vars")
- **Reference examples in clan-core**: `hello-world` (minimal + split roles + eval/VM tests), `sshd` (vars + CA certs + cross-role reads), `wireguard` (multi-role + multi-instance + vars + exports + darwin), `zerotier` (constraints + service-scope exports), `borgbackup` (vars + client/server), `mosquitto` is NOT core — it's community; `pki` (exports consumer), `yggdrasil`/`installer` (selectExports consumers), `users`/`wifi` (attrsOf settings).
- **Community examples**: `~/clan-community/services/{mosquitto,wireguard-star,localsend,authelia,pocket-id,webapps,desktop,dm-*,coredns,wifi,punchcard}`.

---

## 1. Mental model

A clanService is a **module with `_class = "clan.service"`**, registered in
`clan.modules`, and instantiated through `inventory.instances`:

```
flake.nix / clan.nix                      # registers:   clan.modules."<name>" = <module>
inventory.nix / inventory.json            # instantiates: inventory.instances.<instanceName>
                                            module.name / module.input → which service
                                            roles.<role>.machines / .tags / .settings
service module                            # declares:    manifest, roles (+interface+perInstance),
                                                         perMachine, exports
                │
                ▼  (clan-core maps instances × roles × machines)
per-machine NixOS / nix-darwin modules    # consumed by: nixosConfigurations.<machine>
```

Evaluation order that matters when authoring:

1. `roles.<r>.interface` is a **deferred, machine-agnostic module** — it only
   declares *options*. No machine `config` exists here. `meta` (e.g.
   `meta.domain`, `meta.name`) *is* available as a module argument.
2. Settings from inventory are merged (`role.settings` ← `machines.<m>.settings`)
   and evaluated against the interface → `settings`.
3. `perInstance` is applied **once per (instance × machine of that role)**;
   `perMachine` **once per machine in any instance**. Each returns
   `nixosModule` / `darwinModule` / `exports`, which clan-core collects into
   the target machine's module list (`result.final` in the spec).

An **instance** is one deployment of the service (e.g. `wireguard-homelab`,
`wireguard-office`). A **role** is a behavior within it (`peer`, `controller`,
`client`, `server`, `default`).

---

## 2. Directory layout & naming per repo

### clan-core (official)

```
clanServices/<name>/
├── default.nix        # the service module (may import sibling files)
├── flake-module.nix   # registration + tests
├── README.md          # manifest.readme source + user docs
├── *.nix / *.py       # optional helper modules/scripts
└── tests/
    ├── eval-tests.nix # nix-unit eval tests
    └── vm/            # NixOS VM tests (clan.nixosTests)
```

- `clanServices/flake-module.nix` auto-imports every subdir that has a
  `flake-module.nix` (`builtins.readDir` filter). **No central list.**
- `manifest.name = "clan-core/<name>"` (error-context name).
- Registration attr is the bare name (the input provides the namespace):
  `clan.modules.sshd = module;` — consumers use
  `module.name = "sshd"; module.input = "clan-core"` or `module.name = "@clan/sshd"`.
- New core services are expected to ship eval tests (unified into
  `checks.<system>.eval-tests`) and, where meaningful, VM tests.

### clan-community

```
services/<name>/
├── default.nix        # _class = "clan.service"
├── flake-module.nix   # clan.modules.<name> = module; (+ tests)
└── README.md
```

- `services/flake-module.nix` auto-discovers the same way. README.md states
  the contract explicitly: create dir, `default.nix`, `flake-module.nix`,
  `README.md` — "The service is auto-discovered — no central registration
  needed."
- Community services use **unprefixed** names: `manifest.name = "mosquitto"`,
  `clan.modules.mosquitto = module;`. Consumers:
  `module.input = "clan-community"`.
- Community tests use `nix-unit` directly:
  `nix-unit.tests.<name> = import ./tests/eval-tests.nix { inherit module clanLib; };`
  with `clanLib = inputs.clan-core.lib;`.

### This repo (home flake, `github.com/andrewthomaslee/home`)

- `clanServices/<name>/flake-module.nix` registers
  `clan.modules."@andrewthomaslee/<name>" = ./default.nix;` — the
  `@<user>/` prefix is the community guide's collision-free namespacing
  recommendation.
- `clanServices/flake-module.nix` auto-imports subdirs; `flake-parts/default.nix`
  imports it once.
- Instances live in `inventory.nix`; this repo is **static-gates-only** (no VM
  testing), upstream-style VM/eval tests are described in §10 for when the
  service is upstreamed.

---

## 3. Module skeleton

Minimal valid module (`hello-world` shape). Note: a module with no roles
throws at eval, and no instances → eval error, so "minimal" still means
"one role":

```nix
# clanServices/my-service/default.nix
{ ... }:
{
  _class = "clan.service";
  manifest.name = "clan-core/my-service";            # or "my-service" (community) / "@andrewthomaslee/my-service" (home)
  manifest.description = "One line, used in listings/errors";
  manifest.categories = [ "Network" ];               # freedesktop enum, see table
  manifest.readme = builtins.readFile ./README.md;   # empty → eval WARNING

  roles.default = {
    description = "What this role does to a machine"; # null → eval WARNING
    interface = { lib, ... }: {
      options.port = lib.mkOption {
        type = lib.types.port;
        default = 8080;
        description = "Port the service listens on";
      };
    };
    perInstance = { settings, instanceName, machine, roles, meta, ... }: {
      nixosModule = { pkgs, ... }: {
        systemd.services."my-service-${instanceName}" = {   # ← namespace by instanceName!
          wantedBy = [ "multi-user.target" ];
          serviceConfig.ExecStart = "${pkgs.my-service}/bin/my-service --port ${toString settings.port}";
        };
        networking.firewall.allowedTCPPorts = [ settings.port ];
      };
    };
  };

  # Optional: one module per participating machine, regardless of role:
  perMachine = { machine, instances, meta, ... }: {
    nixosModule = { ... }: { /* runs on every machine of any instance */ };
  };
}
```

Header arguments available at module level (injected by clan-core):
`lib, config, clanLib, directory, meta, exports, name, _ctx, ...` — take what
you need (`{ clanLib, config, lib, ... }:` is the most common core-service
header; `{ lib, ... }:` suffices for simple ones).

---

## 4. Manifest reference (`manifest.*`)

| Option | Type / default | Notes |
|---|---|---|
| `name` | str, **required** | Error context + scope identity. `clan-core/<name>` (core), bare `<name>` (community), `@<user>/<name>` (personal flakes). |
| `description` | str, `"No description"` | One line. |
| `readme` | str, `""` | **Eval warning when empty.** Core/community: `builtins.readFile ./README.md`. |
| `categories` | listOf enum, `["Uncategorized"]` | Freedesktop registry: `Audio AudioVideo Desktop Development Education Game Graphics Network Office Science Settings Social System Uncategorized Utility Video`. |
| `maintainers` | listOf (str \| submodule), `[]` | Str coerces to `{name}`. Submodule: `name`, `github`, `email`, `matrix` (matrix e.g. `@user:matrix.org`). |
| `constraints.maxInstances` | nullOr positive int, `null` | Enforced as error-level `cliCheck` when exceeded. |
| `constraints.roles.<r>.minMachines` / `.maxMachines` | nullOr int, `null` | Per-role machine-count bounds per instance, error-level `cliChecks`. Keys must match defined roles. |
| `features.API` | bool | Converts every `roles.<r>.interface` to a JSON schema; **asserts JSON-serializability** of all interfaces (see §8). |
| `exports.out` / `exports.inputs` | listOf str, `[]` | Declare which export interfaces this service provides / consumes (documentation + intent). |

Eval **warnings** (not errors) to keep clean: missing `roles.<r>.description`,
missing/empty `manifest.readme`.

Constraint example (`zerotier`):

```nix
manifest.constraints.roles.controller.maxMachines = 1;
manifest.constraints.roles.controller.minMachines = 1;  # exactly one controller
manifest.constraints.roles.moon.maxMachines = 4;        # zerotier-idtool 1.x limit
```

---

## 5. Roles

Role naming conventions (from the official guide):

- All machines relate equally / talk peer-to-peer → **`peer`** (optionally
  `controller` for an elevated machine, as in `wireguard`/`zerotier`).
- Classic elevated-middle topology → **`client` + `server`** (`borgbackup`,
  `sshd`, `matrix-synapse`).
- Single behavior → one role named **`default`** (`mosquitto`, `wifi`,
  `packages`).
- Machines with *no* relation to each other → reconsider; that's probably
  not a multi-host service.

Instance roles are validated: `instances.<i>.roles.<r>` where `<r>` is not
defined by the service throws with a helpful diff of allowed roles.

### Splitting role implementations

Keep the `interface` (the service's public API surface) visible in
`default.nix`; move bulky `perInstance` into sibling files via `imports`
(`hello-world` pattern):

```nix
# default.nix
{
  _class = "clan.service";
  manifest.name = "clan-core/hello-world";
  # ...
  roles.morning = {
    description = "A morning greeting machine";
    interface = { lib, ... }: { options.greeting = lib.mkOption { type = lib.types.str; default = "Good morning"; }; };
    perInstance = { settings, machine, ... }: {
      nixosModule = { ... }: {
        environment.etc.hello.text = "${settings.greeting} World! I'm ${machine.name}";
      };
    };
  };
  roles.evening = {
    description = "An evening greeting machine";
    interface = { lib, ... }: { options.greeting = lib.mkOption { type = lib.types.str; default = "Good evening"; }; };
  };
  imports = [ ./evening.nix ];   # evening.nix adds roles.evening.perInstance
}

# evening.nix
{
  roles.evening.perInstance = { settings, machine, ... }: {
    nixosModule = { pkgs, ... }: {
      environment.etc.hello.text = "${settings.greeting} World! I'm ${machine.name}";
      environment.systemPackages = [ (pkgs.writeShellScriptBin "greet-world" "cat /etc/hello") ];
    };
  };
}
```

Shared interface fragments between roles: define once as a deferred module and
`imports = [ sharedInterface ];` inside each role's interface (`wireguard`
does this for `port`/`domain`/`mtu`).

---

## 6. `perInstance` — full contract

`roles.<r>.perInstance` maps over every (instance × machine-of-this-role).
Type is `deferredModuleWith` static modules, so it *looks like* a function.

Arguments (specialArgs):

| Arg | Shape |
|---|---|
| `settings` | This machine's evaluated role settings: `roles.<r>.interface` ← `instances.<i>.roles.<r>.settings` ← `...machines.<m>.settings` |
| `instanceName` | str — **namespace everything global with it** |
| `machine` | `{ name = "..."; roles = [ "client" ... ]; }` — this machine's roles **in this instance** |
| `roles` | All roles of the instance, cross-role readable: `roles.<other>.machines.<m>.settings` |
| `meta` | Inventory meta: `meta.domain`, `meta.name` |
| `exports` | Fleet-wide export scope (read) |
| `mkExports` | `data → { "<ownScopeKey>" = data; }` — the **only** sanctioned write |
| `extendSettings` | `module → settings` — experimental local override (§7) |

Returns: `{ nixosModule; darwinModule; exports; }` (each optional).

### Reading other roles' settings (cross-role coordination)

From `sshd` — the client reads all servers' settings to build a merged
trust picture:

```nix
roles.client.perInstance = { settings, roles, ... }: {
  nixosModule = { config, lib, ... }:
    let
      anyCertificateEnabled = lib.any (m: m.settings.certificate.enable or true)
        (builtins.attrValues (roles.server.machines or { }));
      allServerSearchDomains = lib.uniqueStrings (lib.flatten (lib.mapAttrsToList
        (_: m: m.settings.certificate.searchDomains or [ ]) (roles.server.machines or { })));
    in
    {
      programs.ssh.knownHosts.ssh-ca = lib.mkIf anyCertificateEnabled {
        certAuthority = true;
        publicKey = config.clan.core.vars.generators.openssh-ca.files."id_ed25519.pub".value;
      };
    };
};
```

From `wireguard` — the peer builds its peer list from the controller role:

```nix
roles.peer.perInstance = { instanceName, settings, roles, ... }: {
  nixosModule = { config, clanLib, ... }: {
    networking.wireguard.interfaces."${instanceName}" = {
      peers = lib.mapAttrsToList (name: value: {
        publicKey = clanLib.getPublicValue { machine = name; generator = "wireguard-keys-${instanceName}"; file = "publickey"; flake = config.clan.core.settings.directory; };
        endpoint = "${value.settings.endpoint}:${toString value.settings.port}";
      }) roles.controller.machines;
    };
  };
};
```

### Multi-instance namespacing (hard rule)

`perInstance` produces **one module per instance** — they all get imported
into the same machine. Anything global must be namespaced by `instanceName`:
systemd units, launchd daemons, generator names, wireguard interfaces,
firewall rules keyed per-instance, etc. This is stated verbatim in the spec's
option descriptions; upstream does it everywhere:
`systemd.services."webly-${instanceName}"`,
`clan.core.vars.generators."wireguard-network-${instanceName}"`,
`networking.wireguard.interfaces."${instanceName}"`.

---

## 7. `perMachine` and `extendSettings`

`perMachine` maps over every machine participating in **any** instance.
Arguments: `machine` (`{name; roles}` — roles across *all* instances),
`instances` (full evaluated scope: `instances.<i>.roles.<r>.machines.<m>.settings`),
`meta`, `exports`, `mkExports`.

**There is no `settings` argument — accessing it throws** (by design:
settings are always role-scoped). Use `perInstance` or read through
`instances.<i>.roles.<r>.machines.<m>.settings`.

Typical uses: per-machine vars generators keyed by instance, assertions
about cross-role conflicts (`wireguard`):

```nix
perMachine = { instances, machine, ... }: {
  nixosModule = { pkgs, lib, ... }: {
    assertions = lib.flatten (lib.mapAttrsToList (instanceName: instanceInfo:
      let
        isController = instanceInfo.roles ? controller && instanceInfo.roles.controller.machines ? ${machine.name};
        isPeer = instanceInfo.roles ? peer && instanceInfo.roles.peer.machines ? ${machine.name};
      in lib.optional (isController && isPeer) {
        assertion = false;
        message = "Machine '${machine.name}' cannot have both 'controller' and 'peer' roles in wireguard instance '${instanceName}'.";
      }) instances);

    # one keypair generator per instance this machine is in:
    clan.core.vars.generators = lib.mapAttrs' (name: _:
      lib.nameValuePair "wireguard-keys-${name}" {
        files.publickey.secret = false;   # other machines read this
        files.privatekey = { };
        runtimeInputs = [ pkgs.wireguard-tools ];
        script = ''
          wg genkey > $out/privatekey
          wg pubkey < $out/privatekey > $out/publickey
        '';
      }) instances;
  };
};
```

`extendSettings` (experimental, `perInstance` only) — local, machine-dependent
defaults that the interface cannot express (machine `config` is unavailable
at interface time):

```nix
perInstance = { extendSettings, ... }: {
  nixosModule = { config, ... }:
    let
      localSettings = extendSettings {
        ipRanges = lib.mkDefault config.network.ip.range;
      };
    in {
      # localSettings.ipRanges — visible ONLY on this machine.
    };
};
```

⚠️ `extendSettings` results are **local**: other machines reading
`roles.<r>.machines.<m>.settings` do **not** see them (exposing them
fleet-wide would be a performance penalty — per the official guide).

---

## 8. Interfaces & JSON-serializability

`roles.<r>.interface` is a deferred module of **option declarations** only.
Rules:

- Machine `config` is NOT available; `meta` IS (`{ meta, ... }:` for defaults
  like `default = meta.domain`).
- Keep interfaces **JSON-serializable**: plain str/int/bool/list/attrsOf/
  submodule options with serializable defaults/examples. This is asserted
  when `manifest.features.API = true` (each interface gets converted to a
  JSON schema via `clanLib.jsonschema.fromModule`).
- Machine/instance-dependent defaults belong in `perInstance`
  (`extendSettings`) or as explicit inventory settings, not in the interface.
- Good interface hygiene (seen across core): always `type`, `default`
  (or `defaultText`), `description`, `example`.

Interface shape used everywhere:

```nix
interface = { lib, ... }:
let inherit (lib) mkOption types;
in {
  options = {
    port = mkOption { type = types.port; default = 1883; description = "Port for MQTT listener"; };
    users = mkOption {
      type = types.attrsOf (types.submodule {
        options.acl = mkOption { type = types.listOf types.str; default = [ "readwrite #" ]; description = "ACL rules"; };
      });
      default = { };
      description = "MQTT users and their ACL rules";
    };
  };
};
```

---

## 9. Vars (secrets) — the full pattern

Services needing secrets define generators **inside a `nixosModule` /
`darwinModule`** under `clan.core.vars.generators.<name>`.

```nix
clan.core.vars.generators.myapp = {
  files."myapp.key" = { };                          # secret (default true), deployed (default true)
  files."myapp.key.pub".secret = false;             # public: committed in cleartext
  files."ca.crt" = { deploy = false; secret = false; };  # read by OTHER machines, not deployed here
  runtimeInputs = [ pkgs.openssl ];
  script = ''
    openssl genpkey -algorithm ed25519 -out "$out"/myapp.key
    openssl pkey -in "$out"/myapp.key -pubout -out "$out"/myapp.key.pub
  '';
};
```

File attributes: `.secret` (default `true`), `.deploy` (default `true`),
generator-level `share = true` (one value shared fleet-wide instead of
per-machine — used for CAs: `sshd`'s `openssh-ca`, `borgbackup`'s keys).

Generator attributes seen in core services:
- `runtimeInputs` — packages on PATH in the script.
- `dependencies = [ "other-generator" ... ]` — runs after; inputs mounted
  read-only at `$in/<dep>/` (`sshd`'s `openssh-cert` signs with
  `$in/openssh-ca/id_ed25519`).
- `validation.<name> = <value>` — invalidates/regenerates when the value
  changes (`sshd`: `validation = { name = machine.name; domains = ...; }`;
  `wireguard`: `validation.hostname = machine.name`).
- Consuming: `config.clan.core.vars.generators.<g>.files.<f>.path` (runtime
  path on the machine), `.value` (cleartext for non-secret files),
  `.exists` (guard with `lib.mkIf ... .exists` before referencing `.path`,
  see `sshd` host certificate).

Settings-driven generators (`mosquitto` — one secret file per user setting):

```nix
perInstance = { settings, ... }: {
  nixosModule = { config, lib, pkgs, ... }:
    let generator = config.clan.core.vars.generators.mosquitto;
    in {
      clan.core.vars.generators.mosquitto = {
        files = lib.mapAttrs' (name: _: lib.nameValuePair "${name}-password" { secret = true; }) settings.users;
        script = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: _: ''
          password=$(openssl rand -base64 24)
          echo -n "$password" > $out/${name}-password
        '') settings.users);
        runtimeInputs = [ pkgs.openssl ];
      };
      services.mosquitto = {
        enable = true;
        listeners = [ {
          port = settings.port;
          users = lib.mapAttrs (name: user: {
            inherit (user) acl;
            passwordFile = generator.files."${name}-password".path;
          }) settings.users;
        } ];
      };
    };
};
```

Gate generators by settings with `lib.mkIf` (`sshd`):
`clan.core.vars.generators.openssh-rsa = lib.mkIf settings.hostKeys.rsa.enable { ... }`.

**Reading another machine's public var values** — `clanLib.getPublicValue`:

```nix
clanLib.getPublicValue {
  flake = config.clan.core.settings.directory;   # or module-level `directory`
  machine = "server1";
  generator = "wireguard-keys-${instanceName}";
  file = "publickey";
}
```

Lifecycle: `clan vars generate <machine>` (interactive when needed) → secrets
live under the repo's `vars/` tree (per-machine or shared), never in Nix
source. Full vars reference: the `clan-core` skill.

---

## 10. Exports (experimental)

Structured data shared between machines/instances/services: IPs, hostnames,
endpoints, discovery info. Internal scope keys are
`service:instance:role:machine` — **never construct or parse them by hand**;
use `clanLib` helpers. (Full guide: `docs/src/guides/services/exports.md`.)

### Writing

In `perInstance` / `perMachine` — only at the scope matching your context;
ownership is validated (`clanLib.checkExports`), mismatches are eval errors:

```nix
roles.peer.perInstance = { mkExports, machine, instanceName, settings, ... }: {
  exports = mkExports {
    peer.hosts = [
      { plain = "${machine.name}.${if settings.domain == null then instanceName else settings.domain}"; }
    ];
  };
};
```

Service/instance-scope writes (service owns its own scope) go in the
top-level `exports` option, e.g. `zerotier`/`wireguard`/`wireguard-star`
declare instance-level networking metadata:

```nix
# module header needs { clanLib, config, lib, ... }
manifest.exports.out = [ "networking" "peer" ];
exports = lib.mapAttrs' (instanceName: _: {
  name = clanLib.buildScopeKey { inherit instanceName; serviceName = config.manifest.name; };
  value = { networking.priority = 1000; };
}) config.instances;
```

Declare interfaces in the manifest: `manifest.exports.out = [ "networking" "peer" ];`
(provides) / `manifest.exports.inputs = [ "endpoints" ];` (consumes, e.g.
`pki`, `dm-dns`).

### Reading

```nix
# by query (all params optional, default "*"):
allVpn = clanLib.selectExports { service = "vpn"; instance = "homelab"; } exports;
mine   = clanLib.selectExports { machine = machine.name; } exports;

# by predicate (pki):
machineExports = clanLib.selectExports (scope: scope.machineName == machine.name) exports;

# single value:
ep = clanLib.getExport { serviceName = "myservice"; machineName = "backend01"; } exports;
```

Helper reference (`clanLib`): `buildScopeKey { serviceName; instanceName; roleName; machineName; }`,
`parseScope`, `getExport`, `selectExports`.

Consumer example (`pki` — collects endpoints exports fleet-wide and mints
per-endpoint TLS certs):

```nix
manifest.exports.inputs = [ "endpoints" ];
roles.default.perInstance = { machine, exports, ... }: {
  nixosModule = { config, lib, ... }:
    let
      machineExports = clanLib.selectExports (scope: scope.machineName == machine.name) exports;
      allHosts = lib.concatLists (lib.mapAttrsToList (_: v: v.endpoints.hosts or [ ]) machineExports);
    in { /* ... */ };
};
```

### Scope rules (enforced)

1. `perInstance` writes only its own instance/role/machine scope.
2. `perMachine` writes only its own machine scope.
3. A service only ever writes its **own** service scope.
Use `mkExports` — it builds the correct key for your context automatically.

---

## 11. Cross-machine coordination: vars vs exports (decision guide)

- **Vars generators**: values that must be *generated once and kept secret*
  (keys, passwords), or public values derived per-machine (public keys,
  allocated IPs/prefixes). Read cross-machine via `getPublicValue` /
  `files.<f>.value` with `.secret = false`. Works without exports enabled.
- **Exports**: *configuration/discovery* data in structured form consumed by
  other services (`endpoints.hosts`, `networking.priority`, `peer.hosts`).
  Experimental — mark it, use helpers, expect churn.
- Upstream pattern for connectivity services (wireguard/zerotier/yggdrasil):
  **vars for keys + allocations; exports for hostnames/endpoints metadata.**

---

## 12. Assertions, constraints, warnings

- Use NixOS `assertions` inside produced modules for semantic validation
  (`wireguard` role-conflict example in §7).
- Use `manifest.constraints` for countable topology rules (§4) — they become
  error-level `cliChecks`.
- Keep eval **warning-free**: every role needs `description`, the manifest
  needs a non-empty `readme`. Warnings surface during `nix flake check`.

---

## 13. Darwin support

Both `perInstance` and `perMachine` may return `darwinModule` (launchd
daemons, `networking.wg-quick`, etc.). The shared-module pattern for code
that differs per platform (`wireguard`'s `extraHostsModule`):

```nix
extraHostsModule = { instanceName, settings, roles }: { _class, config, lib, ... }:
  let hostsContent = "..."; in
  # mkIf cannot avoid unknown-option errors; branch on _class instead:
  if _class == "darwin"
  then { clan.core.networking.extraHosts.myapp = hostsContent; }
  else { networking.extraHosts = hostsContent; };
```

---

## 14. Passing `self` / `pkgs` / other deps into a service

Dependencies are passed manually. Two upstream-blessed ways
(official guide, "Passing `self` or `pkgs` to the module"):

```nix
# 1. importApply — simpler, preserves error locations
clan.modules."@andrewthomaslee/messaging" =
  lib.modules.importApply ./clanServices/messaging { inherit self; };

# service file takes the arg: { self }: { _class = "clan.service"; ... }

# 2. wrapper module — downstream can override the injected value
clan.modules."@andrewthomaslee/messaging" = {
  options.myClan = lib.mkOption { default = self; };
  imports = [ ./clanServices/messaging ];
};
```

Note: a clan flake can inject arguments fleet-wide via the inventory
`#specialArgs` mechanism (`directory`, `clanLib`, `exports`, plus whatever
the clan flake adds) — check the target flake's clan config before reaching
for either trick. Prefer plain module arguments when the value is already
injected; use the wrapper when it must be overridable per consumer.

---

## 15. Registration (per repo)

### clan-core

`clanServices/<name>/flake-module.nix` — registration + tests:

```nix
{ self, inputs, lib, ... }:
let module = ./default.nix;
in {
  clan.modules.hello-world = module;

  perSystem = { ... }: {
    # eval tests (nix-unit), unified into checks.<system>.eval-tests:
    imports = [
      (self.clanLib.test.flakeModules.makeEvalChecks {
        inherit module inputs;
        fileset = lib.fileset.unions [
          ../../clanServices/hello-world
          ../../nixosModules
        ];
        testName = "hello-world";
        tests = ./tests/eval-tests.nix;
        testArgs = { };
      })
    ];

    # VM tests:
    clan.nixosTests.hello-service = {
      imports = [ ./tests/vm/default.nix ];
      clan.modules.hello-service = module;
    };
  };
}
```

### clan-community

```nix
{ inputs, ... }:
let
  module = ./default.nix;
  clanLib = inputs.clan-core.lib;
in {
  clan.modules.mosquitto = module;
  perSystem = { ... }: {
    nix-unit.tests.mosquitto = import ./tests/eval-tests.nix { inherit module clanLib; };
  };
}
```

### home repo

`clanServices/<name>/flake-module.nix`:
`clan.modules."@andrewthomaslee/<name>" = ./default.nix;`
(no per-system wiring — static gates only). Instance declarations live in
`inventory.nix`:

```nix
instances.my-service = {
  module.input = "self";
  module.name = "@andrewthomaslee/my-service";
  roles.default.tags = [ "all" ];
  # or explicit:
  # roles.server.machines."kamrui-h1".settings.port = 8080;
};
```

---

## 16. Using services — inventory authoring (what users write)

```nix
inventory.instances = {
  # instance name defaults to module name:
  sshd.roles.server.tags = [ "all" ];

  # multiple instances of one module:
  user-sally = {
    module.name = "users";
    roles.default.machines."sally-laptop" = { };
    roles.default.settings.user = "sally";
  };

  # role-wide settings + per-machine override:
  wifi = {
    roles.default.tags = [ "laptop" ];
    roles.default.settings.networks.home = { };
    roles.default.machines."sally-laptop".settings.networks.office = { };
  };
};
```

- Built-in tags: `all`, `nixos`, `darwin`; custom tags on
  `inventory.machines.<m>.tags`.
- `roles.<r>.extraModules` (listOf deferredModule) can extend an instance
  role from inventory; **string entries are deprecated** (warning) — pass
  modules, not paths-as-strings.
- `= { }` means "include with defaults" — presence is the declaration.

---

## 17. Testing a service

### Eval tests (nix-unit) — the upstream-standard fast gate

Build a throwaway clan with `clanLib.clan` and assert on produced config:

```nix
# tests/eval-tests.nix
{ module, clanLib, ... }:
let
  evaled = clanLib.clan {
    self = { };
    directory = ./..;                       # service dir; needed for vars/fileset
    machines.jon = { nixpkgs.hostPlatform = "x86_64-linux"; };
    machines.sara = { nixpkgs.hostPlatform = "x86_64-linux"; };
    modules.hello-world = module;
    inventory.instances."hello" = {
      module.name = "hello-world";
      module.input = "self";
      roles.morning.machines.jon = { };
      roles.evening.machines.sara.settings.greeting = "Good night";
    };
  };
  jon = evaled.config.nixosConfigurations.jon.config;
in {
  inherit evaled;                            # nix-repl inspection; ignored by nix-unit
  morning_greeting = {
    expr = jon.environment.etc."hello".text;
    expected = "Good morning World! I'm jon";
  };
}
```

### VM tests (`clan.nixosTests`)

```nix
# tests/vm/default.nix
{
  name = "hello-service";
  clan = {
    directory = ./.;
    inventory = {
      machines.peer1 = { };
      machines.peer2 = { };
      instances."test" = {
        module.name = "hello-service";
        module.input = "self";
        roles.morning.machines.peer1 = { };
        roles.evening.machines.peer2.settings.greeting = "Good night";
      };
    };
  };
  testScript = ''
    start_all()
    value = peer1.succeed("greet-world")
    assert value.strip() == "Good morning World! I'm peer1", value
  '';
}
```

### Services with vars

VM tests need generated vars first (see `docs/src/guides/contributing/testing.md`):

```bash
nix run .#checks.x86_64-linux.<test-name>.update-vars   # creates vars/ + sops/ under clan.directory
nix run .#checks.x86_64-linux.<test-name>               # then run the test
# hello-world variant:
nix run .#generate-test-vars -- clanServices/hello-world/tests/vm hello-service
nix build .#checks.x86_64-linux.hello-service
```

---

## 18. Verification & contribution checklist

### Static gates (home repo — mandatory, no VM tests)

1. `git add` the new/changed files **first** — Nix evaluates from the git
   tree; `readDir`-based auto-import misses untracked dirs.
2. `nix fmt .` → `statix check .` → `deadnix --fail .`.
3. `nix flake check --show-trace` — surfaces: interface JSON-serializability
   assertions, export scope-ownership errors, constraint `cliChecks`,
   missing role-description/readme warnings, topology throws (unknown roles,
   no roles, no instances).
4. Eval probes without building:
   `nix eval .#nixosConfigurations.<machine>.config.system.build.toplevel.drvPath`
   and targeted options, e.g.
   `nix eval .#nixosConfigurations.<m>.config.<option> --json`.
5. Read the eval output for warnings — fix before declaring done.

### Upstream readiness

- [ ] `manifest.name` follows repo convention (`clan-core/<n>` / `<n>` / `@user/<n>`)
- [ ] `manifest.readme` set; `README.md` documents what it does, when to use, **roles**, quick-start inventory snippet, options (community README contract)
- [ ] every role has `description`; role names follow §5 conventions
- [ ] JSON-serializable interfaces; machine-dependent defaults moved to `perInstance`/`extendSettings`
- [ ] multi-instance-safe: everything global namespaced by `instanceName`
- [ ] vars: `.secret`/`.deploy` correct; `share` for fleet CAs; `.exists` guards on optional files; `validation` for invalidation
- [ ] exports: helpers only, correct scope, `manifest.exports.{out,inputs}` declared
- [ ] darwin covered (or a deliberate NixOS-only choice) — check `_class` branching, not `mkIf`, for shared modules
- [ ] tests: eval tests minimum (clan-core: also wire into `makeEvalChecks`; VM test where behavior matters; vars → `update-vars` flow documented)
- [ ] for **clan-core** specifically: follow `hello-world` flake-module.nix (eval checks unified into `checks.<system>.eval-tests`) and add `clan.nixosTests.<name>`
- [ ] for **clan-community**: exactly `default.nix` + `flake-module.nix` + `README.md` (+ `tests/`), auto-discovered; add a row to the README service table
- [ ] commit: run the repo formatter (treefmt), keep dead code out (`deadnix`)

---

## 19. Pitfalls (learned from the spec + upstream code)

1. **Don't touch scope keys** — `service:instance:role:machine` is internal;
   always `mkExports`/`selectExports`/`getExport`/`buildScopeKey`.
2. **`perMachine` has no `settings`** — it throws by design; go through
   `instances.<i>.roles.<r>.machines.<m>.settings` or use `perInstance`.
3. **`roles.<r>.settings` (role-wide) warns** — prefer
   `roles.<r>.machines.<m>.settings`; the plain role-settings accessor is
   slated for removal.
4. **`extendSettings` is local-only** — other machines can't see the
   extensions.
5. **Machine config unavailable in `interface`** — use `meta` there; defer
   config-dependent defaults to the produced module or `extendSettings`.
6. **`mkIf` does not prevent unknown-option errors** in a module imported
   into both NixOS and darwin — branch on `_class` (see §13).
7. **Multiple instances on one machine** import all produced modules
   together — any non-namespaced global definition conflicts (spec's own
   example: `systemd.services."webly-${instanceName}"`).
8. **`readFile`d helper scripts** (`./ipv6_allocator.py` etc.) are fine;
   generated-at-eval secrets are not — secrets only via vars generators.
9. **Eval warns, not errors**, for missing `readme`/`description` — CI noise
   upstream treats as review-blocking; keep clean.
10. **Untracked files don't exist for Nix** — `git add` before eval/check.

---

## 20. Recipe index (copy-paste starting points)

| You want… | Copy from |
|---|---|
| Minimal service + split roles | `clan-core/clanServices/hello-world` |
| Client/server + vars + cross-role settings read | `clan-core/clanServices/sshd`, `borgbackup` |
| Multi-role mesh + multi-instance + darwin + getPublicValue | `clan-core/clanServices/wireguard` |
| Constraints (exactly-one controller) + service-scope exports | `clan-core/clanServices/zerotier` |
| Settings-driven secret files (attrsOf → files) | `clan-community/services/mosquitto` |
| Community-style topology service with exports | `clan-community/services/wireguard-star` |
| Exports consumer (`inputs`, predicate selectExports) | `clan-core/clanServices/pki` |
| Eval test via `clanLib.clan` | any `*/tests/eval-tests.nix` |
| VM test with vars | `clan-core/clanServices/*/tests/vm` + testing.md |
| Machine classification service | home `clanServices/machine-type`, `tags` |
