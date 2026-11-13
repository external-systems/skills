---
name: remote-builder
description: "Use, test, and debug the external-systems org's euc-hel-0 Nix remote builder: normal distributed package builds, proving real remote compilation, forcing local builds, NixOS VM tests, SSH/store diagnostics, and clanService eval tests. Load whenever building Nix packages or machine closures, offloading VM tests, or troubleshooting remote builds in this org."
---

# remote-builder

Use euc-hel-0 through the Nix daemon's configured distributed builders.
It is currently the org's only deployed builder. Every `pc`-tagged clan
machine is a client; do not assume an unlisted machine has access.

The client configuration already contains the builder, SSH alias, root-only
client key, and pinned host key. Normal builds need no SSH command, remote
store flag, or Nix configuration edit.

## Choose the build mode

### Normal: let Nix schedule the build

Run the repository's ordinary command:

```sh
nix build .#<attr> -L
```

Nix prefers a compatible remote builder by default and can fall back to the
local machine when none is available. The builder advertises `x86_64-linux`
and emulated `aarch64-linux`, 16 concurrent jobs, speed factor 10, and the
features `benchmark`, `big-parallel`, `kvm`, and `nixos-test`. Speed factor
ranks builders; it does not mandate remote placement. Derivations marked
`preferLocalBuild` stay local when possible. `aarch64-linux` uses emulation
and can be slower than native x86_64 builds.

Keep substituters enabled for normal work. Both client and server use
`builders-use-substitutes`, so the builder can fetch dependencies directly
from binary caches instead of receiving them from the client. Results are
copied back to the client. Treat the builder's store as a cache, not an
archive: garbage collection can remove unreferenced outputs.

### Force one build to compile locally

Clear the remote-builder list only for that invocation:

```sh
nix build --builders '' .#<attr> -L
```

This changes no persistent configuration; later commands use euc-hel-0
again. It forces compilation locally but still permits cache substitution.
For a local compile test that must also reject cached outputs, use a fresh
derivation or disable substituters deliberately for that test.

Do not use `--max-jobs 0` for this: zero local jobs disables local builds.

### Prove that remote compilation works

First check the same root-only connection the daemon uses:

```sh
sudo -n nix store info --store ssh-ng://euc-hel-0
```

A healthy result reports the remote Nix version and `Trusted: 1`. The
restricted `nix-ssh` account serves a store, not a login shell, so an
interactive SSH failure is not a builder failure.

Then build a fresh derivation with local jobs and substituters disabled:

```sh
nix build --impure --expr \
  'with import <nixpkgs> {}; runCommand "remote-builder-proof-${toString builtins.currentTime}" {} "echo remote-ok > $out"' \
  --max-jobs 0 --option substituters '' -L --no-link --print-out-paths
```

The unique name prevents an existing output from hiding a skipped build.
Success requires a log line like:

```text
building '...drv' on 'ssh-ng://nix-ssh@euc-hel-0'...
```

For a real package, `nix build --max-jobs 0 -L .#<attr>` disables ordinary
local compilation; `preferLocalBuild` derivations are the exception. Add
`--option substituters ''` only when the test must compile rather than
substitute, and make sure the output is not already built. Do not add
`--rebuild` to the zero-local-jobs proof: on the deployed Nix version that
combination can fail instead of dispatching the rebuild.

## NixOS VM tests and large builds

Use the repository's `vm-test` runner (org-pkgs `flakeModules.vmTests`;
the `vm-tests` skill) or build its test derivation.
The remote builder's `kvm` and `nixos-test` features satisfy the usual
NixOS VM-test requirements, and `big-parallel` suits large derivations.
Nix routes derivations by system and required features; a feature the
builder does not advertise cannot be silently ignored.

```sh
vm-test <test> --remote            # only on the remote builders (--max-jobs 0)
vm-test <test> --remote --rebuild  # boot it again although it passed before
vm-test --all --remote --rebuild   # every test, side by side within vmTests.parallel
# Or build the derivation directly:
nix build --max-jobs 0 -L .#legacyPackages.x86_64-linux.vmTests.<test>
```

A result that is already in the builder's store comes back without
booting anything; `vm-test` reports that as CACHED, not as a pass of
this run. `vm-test --rebuild` gets a fresh run by building a per-run
copy of the test (`vmTestsFresh`), which the builder accepts; plain
`nix build --rebuild` with `--max-jobs 0` fails (see above).

A runner may perform its own nested `nix build`; flags given to `nix run`
do not automatically become flags for that nested build. Use the runner's
`--remote` flag (or `-- <nix build args>`) when forcing placement, and check `-L` output
when proof matters. Driver or interactive mode runs the VMs on the invoking
machine; use the sandboxed build for remote execution. VM tests stay out of
`checks`, and GitHub Actions never runs them or uses this builder.

## Debug from the client

Start with the error's build phase. Evaluation, input copying, remote
execution, and result copying have different causes.

1. Run the build with `-L`; retain the first failing derivation and the
   builder named in the log.
2. Check daemon-visible configuration without printing private keys:

   ```sh
   sudo -n cat /etc/nix/machines
   sudo -n nix store info --store ssh-ng://euc-hel-0
   journalctl -u nix-daemon -b
   ```

   The machine entry should name `euc-hel-0`, both Linux systems, 16 jobs,
   speed factor 10, and the four features above. The key path is expected
   to be root-only because nix-daemon, not the calling user, opens SSH.
   When investigating an older incident, widen the journal time range;
   `-b` covers only the current boot.
3. Match the symptom to the next action:

| Symptom | Meaning and response |
|---|---|
| Build runs locally | Scheduling is allowed, not necessarily broken. Use the fresh-derivation proof when placement must be verified. |
| `Host key verification failed` or host key changed | The pinned host key no longer matches, commonly after a server reinstall. Do not disable host-key checking or delete the mismatch by hand. Verify the current public host-key var and client known-hosts generation; a human updates the source and redeploys. |
| `Permission denied (publickey)` | The client key is missing, unreadable by root, or not authorized on the server. Check vars presence and deployment state without printing either private half. A new client needs vars generation, then a server deploy to authorize its public key, then a client deploy. |
| Connection timeout or refused | Check reachability and the server service. The configured alias fails after 5 seconds; with local jobs enabled Nix can fall back to local builds, while `--max-jobs 0` makes the failure explicit. |
| Required feature or system has no builder | Compare the derivation's system and `requiredFeatures` with `/etc/nix/machines`. VM tests need `kvm` and `nixos-test`; cross-system builds depend on the advertised emulated system. |
| Remote-only build failure | Inspect the `-L` remote build log and compare resources, emulation, and required features with a local run. A started remote build that fails does not automatically retry locally; fix the cause or rerun deliberately. |

Remote build logs are copied back, so local `nix log <drv>` can inspect a
completed attempt. `nix log --store ssh-ng://...` is not a supported
debugging path for this setup. Never work around authentication by copying
a client private key into a repository, command line, or user-writable
location.

## Test or change the clanService

The implementation and its tests live in external-systems/clanServices:

- `services/remote-builder/default.nix` — server/client modules.
- `services/remote-builder/tests/eval-tests.nix` — throwaway-clan tests for
  generators, SSH serving, build machines, aliases, and multi-instance
  namespacing.
- `services/remote-builder/flake-module.nix` — service and test registration.

After editing, stage new files before Nix evaluation, then run:

```sh
nix fmt .
nix build .#checks.x86_64-linux.nix-unit -L
nix flake check --show-trace
```

The focused check runs all service eval tests, including remote-builder.
When changing supported features or SSH timeouts, update their expected
values in `eval-tests.nix`; those assertions are intentional drift guards.
The service has no VM suite. Test inventory wiring separately in
external-systems/home with its full `nix flake check`; home's current
`remote-builder` instance assigns `server` to euc-hel-0 and `client` to the
`pc` tag.

Agents do not deploy. Report the required human operation instead: generate
new vars, update the server before new clients, then update clients. Keep
server addresses in the values flake, never in this public skill.

## CI and trust boundary

Outside clan clients, CI can use the instance's shared CI key and an explicit
`--builders` entry or remote store. Only an operator should retrieve that
private key; it is never deployed by the service. Do not assume existing CI
uses the builder: home's current GitHub Actions workflow runs on
`ubuntu-latest` without it. Treat every authorized key as root on the
builder's store: `nix.sshServe` enables trusted writes.

## Source of truth

Re-read these files when behavior may have changed:

- `~/external-systems/clanServices/services/remote-builder/`
- `~/external-systems/home/inventory.nix`
- `~/external-systems/home/documentation/docs/fleet/remote-builder.md`
