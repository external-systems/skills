---
name: vm-tests
description: "Hermetic NixOS VM tests in external-systems org repos: org-pkgs flakeModules.vmTests (vm-tests/*.nix auto-discovered into legacyPackages.SYSTEM.vmTests, never checks), the vm-test runner (--list, NAME, --all/--serial, --check, --remote on euc-hel-0, parallel --all within a vCPU/memory budget with failures rerun alone, fresh --rebuild runs and CACHED results, --quiet and the run summary, --driver/--keep-state/--interactive), vmTests.* options, eval-only checks and resource caps, hermetic fake secrets for clan-vars modules, clan tests vs plain tests, pitfalls that cost a run, recipes (offline ACME, browser trust, LAN clients, config changes), debugging, and the agent loop. Load when creating, running, or debugging a VM test."
---

# vm-tests

NixOS integration tests: QEMU VMs booted by the NixOS test driver. Every
external-systems repo gets the wiring from org-pkgs
`flakeModules.vmTests`, part of `flakeModules.default`. A repo writes test
files only. The module's source is `flakeModules/vm-tests.nix` in
external-systems/pkgs, and its docs page is `documentation/docs/vm-tests.md`
there.

## Hard rules

- **VM tests never run in GitHub Actions.** org-ci.yml runs `nix flake
  check`, the release and the docs deploy, nothing else. Never add a
  VM-test job, label, workflow_dispatch input or builder secret to any
  workflow, and never give CI the remote builder.
- **Never in `checks`.** Tests are `legacyPackages.<system>.vmTests.<name>`.
  `checks.vm-tests-no-kvm-checks` fails if any check needs KVM.
- **Manual only:** a person or agent runs `vm-test` on a local KVM machine
  or offloads it to the remote builder (euc-hel-0: x86_64 + aarch64,
  features `kvm nixos-test big-parallel`, 16 jobs; see the
  `remote-builder` skill).
- **Hermetic.** No network inside the VMs, nothing downloaded at boot,
  everything asserted is in the Nix closure, no host state. Never
  `--no-sandbox`, `sandbox = false` or `__noChroot`. A test that exists to
  check network behaviour says so in the file and in the PR.
- **KVM is mandatory.** The module sets `requiredFeatures.kvm = true` and
  `qemu.forceAccel = true`, so a builder without KVM refuses the job
  instead of running it emulated. There is no TCG fallback.
- **No size variants.** Each test declares the resources it needs on its
  nodes. The attribute name is the file's basename.

## Writing a test

`vm-tests/<name>.nix` is a `nixosLib.runTest` module (not
`pkgs.testers.nixosTest`). Files starting with `_` or `.` are helpers, not
tests. `git add` the file before any `nix` command.

```nix
# vm-tests/my-service.nix
{self, ...}: {
  nodes.machine = {pkgs, ...}: {
    imports = [self.nixosModules.my-service];
    services.my-service.enable = true;
    environment.systemPackages = [pkgs.curl];
    # Undeclared = 1024 MiB, 1 core. Declare what the test needs.
    virtualisation = {
      memorySize = 2048;
      cores = 2;
    };
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("my-service.service", timeout=120)
    machine.wait_until_succeeds("curl -sf http://127.0.0.1:8080/healthz", timeout=60)
  '';
}
```

What the module provides for every test:

| Setting | Value |
|---|---|
| module args | `self`, `inputs` and `vmTests.specialArgs`, in the test module **and** every node module |
| `defaults` | `vmTests.defaults`, applied to every node |
| `hostPkgs` | the repo's perSystem `pkgs` |
| `name` | the file's basename (`mkDefault`) |
| `globalTimeout` | `vmTests.globalTimeout` (1800 s) unless the test sets its own |
| `requiredFeatures.kvm`, `qemu.forceAccel` | `true` |

`testScript` is Python. `machine.succeed(cmd)` asserts exit 0,
`machine.fail(cmd)` asserts non-zero, plus `wait_for_unit(unit,
timeout=N)`, `wait_until_succeeds(cmd, timeout=N)`, `wait_for_open_port`.
Assert with exit codes: `test -f`, `grep -q`, `jq -e` (bracket notation
for hyphenated keys: `jq -e '.mcp["some-server"].type == "remote"'`).

## vmTests options

Set them at the flake's **top level**, not inside `perSystem`. Every
option has a default.

```nix
vmTests = {
  defaults = [self.nixosModules.default];   # every node of every test
  specialArgs = {inherit customLib;};       # extra args besides self, inputs
  systems = ["x86_64-linux"];               # default
  tests.extra = ./tests/extra.nix;          # tests defined in code; name wins over a file
  globalTimeout = 30 * 60;                  # default per-test timeout (s)
  limits = {                                # defaults
    memorySize = 16384;                     # MiB, one VM
    cores = 8;                              # one VM
    totalMemorySize = 24576;                # MiB, all VMs of one test
    totalCores = 16;                        # all VMs of one test
  };
  parallel = {                              # `vm-test --all` budget
    cores = 16;                             # default: limits.totalCores
    memorySize = 24576;                     # default: limits.totalMemorySize
    evalJobs = 4;                           # tests evaluated at once, locally
  };
  flakeChecks.enable = true;                # eval + resources checks in `checks`
  # dir = "${self}/vm-tests";               # default; null disables discovery
};
```

## Running: vm-test

`vm-test` is a devenv script in every repo; outside the shell, use
`nix run .#vm-test --`. It builds from the git tree, so untracked files
are invisible.

| Command | Does |
|---|---|
| `vm-test --list` | list the tests |
| `vm-test <name>` | sandboxed `nix build` of the test; **exit code = result** |
| `vm-test <name> --remote` | the same with `--max-jobs 0`: only the daemon's remote builders (euc-hel-0) |
| `vm-test --all --remote` | every test on the builder, side by side within `vmTests.parallel`, failures rerun alone (below) |
| `vm-test --all --serial --remote` | the same, one test at a time |
| `vm-test --check [<name>]` | every test (or one) evaluates and fits the caps, one Nix process per test; boots nothing |
| `vm-test <name> --quiet` | the full log goes to `build.log` only; only the summary is printed |
| `vm-test --summary <name>` | print the last run's summary again, without building |
| `vm-test <name> --rebuild` | boot a test that already passed again; works with `--remote` and `--all` |
| `vm-test <name> --driver` | run the driver on this machine, outside the sandbox |
| `vm-test <name> --driver --keep-state` | reuse VM disks between runs (fast iteration) |
| `vm-test <name> --driver --interactive` | Python REPL against live VMs |
| `vm-test <name> -- <args>` | extra `nix build` args |

Every build and driver run ends with a **summary**: each subtest
started, the `!!!` failures, and the first build errors, such as the
test-script linter. It is printed and saved as `summary.txt`. Read the
summary first; open the full log only for what it points at. Output
lands in `.vm-tests/<name>/` in the repo root (gitignored): `build.log`,
`result.txt` (`passed|cached|failed <seconds>`),
`summary.txt` and the `result` link for builds; `driver.log`,
`junit.xml` and screenshots for driver runs. `--all` writes to each
test's own directory.

- **CACHED is not a pass of this run.** A build that succeeds without
  booting anything (the result was already in a store, often the
  builder's) prints `CACHED` and, when the log is available, the earlier
  run's summary. To prove a change, run with `--rebuild`: it builds
  `vmTestsFresh.<name>` (the test with a per-run id, `--impure`), so it
  boots again, also on the remote builder. Plain `nix build --rebuild`
  never goes to a remote builder; do not use it with `--max-jobs 0`.
- **`--all`** prepares `parallel.evalJobs` tests at a time (evaluate,
  check caps, read sizes, build drivers), then boots tests largest first
  while their VMs fit in `vmTests.parallel` (a test larger than the
  budget runs alone). A test that fails with others running is rerun
  alone: passing then is `PASS(!)`, a pass with a warning (timing-
  sensitive under load; first log in `build-under-load.log`). It ends
  with one `PASS`/`PASS(!)`/`CACHED`/`FAIL` line per test and exits
  non-zero on any `FAIL`.

- The flags of the nested `nix build` are the runner's. Flags given to
  `nix run` itself never reach it: use `--remote` or `-- <args>`.
- Without `--remote`, Nix may still pick the remote builder (it prefers
  it). With `--remote`, a builder failure is an error, not a silent local
  fallback.
- Driver mode always runs VMs on the invoking machine and needs
  `/dev/kvm` there. Only sandboxed builds can go remote.
- Never run VM tests inside the OpenShell code-agent sandbox (no KVM). Use
  `--remote` from a machine that has the builder configured, or hand the
  command to the owner.

## What nix flake check covers

When a repo has tests, three eval-only checks run; they boot nothing and
are safe on GitHub runners. A repo whose tests are expensive to evaluate
(many clan suites) sets `vmTests.flakeChecks.enable = false`: the first
two then leave `checks` and stay available as
`legacyPackages.<system>.vmTestChecks` for `vm-test --check`; the KVM
guard always stays.

| Check | Fails when |
|---|---|
| `vm-tests-eval` | a test does not evaluate (its `drvPath` fails) |
| `vm-tests-resources` | a VM's `virtualisation.memorySize` > 16384 MiB or `cores` > 8, or a test's VMs sum > 24576 MiB or 16 cores (`vmTests.limits`; the values are read from the evaluated nodes) |
| `vm-tests-no-kvm-checks` | any check needs `kvm`/`nixos-test` or is a NixOS test |

The caps fit kamrui-h1 (32 GiB, 16 threads). Need more? Split the test
or reduce node count; raising `limits` needs the owner's yes.

## Secrets: hermetic fakes

Tests have no real key material and must not need any.

- **Modules with clan vars:** when a module reads secrets from clan vars
  generators, give it a switch that turns that off and file options to
  point at instead, as `hostSpec.services.openshell.gateway` in
  external-systems/modules does (`provisionSecrets = false`, with each
  secret file option set explicitly). In the test, set
  `provisionSecrets = false` and point the options at fakes.
- **Build fakes at build time** with `pkgs.runCommand` (e.g. `openssl req
  -x509 ... -subj /CN=test` for TLS, `ssh-keygen -N "" -f $out/key`) and
  reference the output paths. Secrets in the store are fine in a test.
  They are never fine in real configs.
- **Simple strings:** `environment.etc."vm-test-token".text = "fake";`,
  with the option pointing at `/etc/vm-test-token`.
- If a module insists on sops, derive the age key from the VM's SSH host
  key (`services.openssh.enable = true`) instead of embedding one.

## Plain tests vs clan tests

- **Plain (default):** import the repo's NixOS modules
  (`vmTests.defaults` or per node) and set the options a clan service
  would set. This is fast and covers most modules. If the module reads
  `clan.core.*`, import `inputs.clan-core.nixosModules.clanCore` and set
  `clan.core.settings = {directory = self; machine.name = "test";}`, or
  use the repo's clan stub module if it has one.
- **Clan tests** (a whole clan service with inventory and vars) wrap
  clan-core's `clanTest` module (`inputs.clan-core.modules.nixosTest.clanTest`,
  with `defaults._module.args.clan-core`) and register in
  `vmTests.tests`, never `clan.nixosTests` (that puts them in `checks`).
  clanServices does this: each service's `flake-module.nix` adds suites
  to a top-level `clanTests.<suite>` option, and
  `flake-parts/clan-tests.nix` hands them to `vmTests.tests` with
  `dir = null`, raised `limits`, `parallel` and
  `flakeChecks.enable = false`. Test vars are generated during
  evaluation (clan-core IFD); there is no update-vars step. Authoring
  details: the `clanservices` skill.

## Debugging

1. Read the summary (`vm-test --summary <name>`): the failing subtest,
   its `!!!` line, or the build error that stopped the test before boot.
   Then open `.vm-tests/<name>/build.log` (or `driver.log`) at that
   subtest for the `must succeed:` line and the journal around it.
2. Iterate with `vm-test <name> --driver --keep-state`: VM disks persist
   between runs, much faster than a cold boot. Run once more without
   `--keep-state` before claiming success.
3. `--driver --interactive`: `start_all()`, then
   `machine.succeed("journalctl -u my-service --no-pager")`,
   `machine.shell_interact()`.
4. `sshBackdoor.enable = true;` in the test gives SSH into each VM over
   vsock during a driver run (the driver prints the commands).
5. `machine.screenshot("name")` and `machine.copy_from_vm(path)` land in
   the output dir.

## Agent loop

1. Mirror an existing test in the repo before inventing conventions.
2. Write `vm-tests/<name>.nix`; `git add` it.
3. `fmt`, then `check`, and `vm-test --check <name>`. The eval-only
   checks catch evaluation errors and resource overruns without booting
   anything.
4. `vm-test <name> --remote --quiet` (add `--rebuild` when a CACHED
   result would hide whether your change still passes), then read the
   summary. For many tests use `vm-test --all --remote --rebuild`: it
   runs them side by side within the budget; never start several
   `vm-test` processes by hand on one builder. On failure, fix
   the **config under test** first; change the test only when the test
   is wrong.
5. Claim a pass only on exit 0 of a sandboxed build that booted the VMs
   (`passed`, not `CACHED`; not a driver run).
   Report the exact command, local or remote, and the result.
6. New services in modules should come with a VM test. A batch across
   repos: `vm-test --all --remote` in each.

## Pitfalls that cost a run

Each of these failed a 10-15 minute remote run in practice.

- **The driver lints `testScript` with ruff before booting.** An unused
  import fails the build (`F401`). Import a module in the test that uses
  it, not in a shared helper string.
- **Read whole streams in pipes:** `cmd | grep X >/dev/null`. `grep -q`
  exits at the first match, the writer gets SIGPIPE (curl exit 23), and
  under the driver's `pipefail` a `succeed` fails on long output while a
  `fail` can pass by accident.
- **`systemctl restart` of a `Type=simple` unit returns before it
  listens** (nginx, most daemons): follow it with `wait_until_succeeds`
  or `wait_for_open_port`, never a bare `succeed` on the service.
- **Reload what the module configures.** A test that never runs
  `systemctl reload <unit>` misses reload-only failures: nginx's reload
  runs `nginx -t` as the nginx user, which cannot read a key passed by
  `LoadCredential`, so deploys and ACME renewals silently kept old
  certificates. Give nginx files it can read (group `nginx`, 0440) and
  assert a reload.
- **A wait that times out says nothing about why** (`curl -sf` is
  silent). Wrap a slow wait in `try`/`except`, print `curl -v`, the
  served certificate chain and the relevant journal, then `raise`.
- **A NixOS module that reads home-manager users' options** needs test
  users built like real ones (the repo's `homeModules.default` and its
  shared modules); a user with one home module made a sibling NixOS
  module recurse infinitely.
- **Headless Firefox never exits on a certificate-error page**
  (`--screenshot` waits forever): run such controls under a short
  `timeout` with `machine.execute` and assert on the server's logs.

Longer patterns (an offline ACME server, proving a browser trusts a
certificate, a LAN client that edits its hosts file, testing a config
change with a specialisation): [references/recipes.md](references/recipes.md).

## Patterns and anti-patterns

Patterns:

- Every wait gets an explicit, generous timeout. Never assume ordering.
- Keep `testScript` to orchestration. Write complex checks as a Python
  probe in the guest (`environment.etc."probe.py".source =
  pkgs.writeText "probe.py" ''...''`), run it with
  `machine.succeed("python3 /etc/probe.py")`, and use plain `assert`.
- Test users with systemd user units: `linger = true`, then start units
  deterministically (`systemctl --user daemon-reload` then `start`, with
  `XDG_RUNTIME_DIR=/run/user/<uid>`). Don't race home-manager activation.
- Small focused tests, 1-3 nodes each.

Anti-patterns:

- Downloads at guest startup (models, images, charts): pre-bake them in
  the closure or switch the feature off.
- Bare `sleep` instead of a readiness wait.
- "Fixing" a failure by loosening the sandbox, adding network, or moving
  the test into `checks` or CI.
- One giant node asserting ten unrelated things.
