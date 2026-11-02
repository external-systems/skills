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

The daemon can choose euc-hel-0 or the local machine. The builder advertises
`x86_64-linux` and emulated `aarch64-linux`, 16 concurrent jobs, speed factor
10, and the features `benchmark`, `big-parallel`, `kvm`, and `nixos-test`.
Speed factor is a preference, not a guarantee that every build leaves the
local machine. `aarch64-linux` uses emulation and can be slower than native
x86_64 builds.

Keep substituters enabled for normal work. Both client and server use
`builders-use-substitutes`, so the builder can fetch dependencies directly
from binary caches instead of receiving them from the client.

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

For a real package, `nix build --max-jobs 0 -L .#<attr>` forbids local
compilation. Add `--option substituters ''` only when the test must compile
rather than substitute, and make sure the output is not already built.
Do not add `--rebuild` to the zero-local-jobs proof: on the deployed Nix
version that combination can fail instead of dispatching the rebuild.

## NixOS VM tests and large builds

Use the repository's normal VM-test runner or build its test derivation.
The remote builder's `kvm` and `nixos-test` features satisfy the usual
NixOS VM-test requirements, and `big-parallel` suits large derivations.
Nix routes derivations by system and required features; a feature the
builder does not advertise cannot be silently ignored.

```sh
nix run .#vm-test -- <test>-sm
# Or, when the test is exposed as a flake package:
nix build .#<test-attr> -L
```

A runner may perform its own nested `nix build`; flags given to `nix run`
do not automatically become flags for that nested build. Use the runner's
documented builder option when forcing placement, and check `-L` output
when proof matters. Keep VM tests out of `checks` in org repos that follow
the `vm-tests` convention.

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
3. Match the symptom to the next action:

| Symptom | Meaning and response |
|---|---|
| Build runs locally | Scheduling is allowed, not necessarily broken. Use the fresh-derivation proof when placement must be verified. |
| `Host key verification failed` or host key changed | The pinned host key no longer matches, commonly after a server reinstall. Do not disable host-key checking or delete the mismatch by hand. Verify the current public host-key var and client known-hosts generation; a human updates the source and redeploys. |
| `Permission denied (publickey)` | The client key is missing, unreadable by root, or not authorized on the server. Check vars presence and deployment state without printing either private half. A new client needs vars generation, then a server deploy to authorize its public key, then a client deploy. |
| Connection timeout or refused | Check reachability and the server service. The configured alias fails after 5 seconds; with local jobs enabled Nix can fall back to local builds, while `--max-jobs 0` makes the failure explicit. |
| Required feature or system has no builder | Compare the derivation's system and `requiredFeatures` with `/etc/nix/machines`. VM tests need `kvm` and `nixos-test`; cross-system builds depend on the advertised emulated system. |
| Remote-only build failure | Inspect the `-L` remote build log and compare resources, emulation, and required features with a local run. A remote store connection succeeding does not prove the derivation itself can build. |

`nix log --store ssh-ng://...` is not a supported debugging path for this
setup. Use the client's build output and daemon journal. Never work around
authentication by copying a client private key into a repository, command
line, or user-writable location.

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
private key; it is never deployed by the service. Treat every authorized key
as root on the builder's store: `nix.sshServe` enables trusted writes.

## Source of truth

Re-read these files when behavior may have changed:

- `~/external-systems/clanServices/services/remote-builder/`
- `~/external-systems/home/inventory.nix`
- `~/external-systems/home/documentation/docs/fleet/remote-builder.md`
