---
name: odoo
description: "Odoo test instances on the owner's machines through external-systems/modules hostSpec.services.odoo: configuring instances (demo data, apps, language, memory, LAN or public exposure), using them (URLs, admin login, Mailpit, odoo-reset, odoo-snapshot, odoo-purge, odoo-hosts, Windows LAN clients), maintaining and changing the module (start sequence, reset copies, package bumps, VM tests), and debugging instances that do not start, crash, run slow or lose mail. Load for any Odoo task on these machines, even when the user only says Odoo, ERP or a machine name like beelink."
---

# odoo

The owner runs Odoo **for testing only**, never production: throwaway
instances that are reset, snapshotted and exposed on purpose. One NixOS
module does all of it: `hostSpec.services.odoo` in external-systems/modules
(`flake-parts/nixosModules/odoo.nix`, scripts in
`flake-parts/nixosModules/_odoo/`, user docs in
`documentation/docs/odoo.md` and `odoo-access.md`, a plain-English page
for non-technical users in `ceo-odoo.md` (with its own deck,
`documentation/slides/ceo-odoo.md`), published at
`https://modules.external.systems/odoo.html`). Machines enable it in
external-systems/home (`machines/<machine>/configuration.nix`; beelink
does). Read the module's header comment before changing it: it is the
design summary.

## The shape

| Per instance `<name>` | Where |
| --- | --- |
| unit, system user, PostgreSQL role and database | `odoo-<name>` (peer auth, no DB password) |
| URL on the machine | `https://<name>.odoo.localhost` |
| URL on the LAN (`expose.lan`) | `https://<name>.odoo.<host>.home.arpa` |
| state: filestore, sessions, markers | `/var/lib/private/odoo-<name>/data` |
| runtime config (holds the master password) | `/run/odoo-<name>/odoo.cfg` |
| reset copy | DB `odoo-<name>@golden`, files `/var/lib/odoo-golden/<name>` |
| snapshots | DBs `odoo-<name>@snap-<tag>`, files `/var/lib/odoo-snapshots/<name>` |

Shared: `https://odoo.localhost` (index), `https://mail.odoo.localhost`
(Mailpit, every mail the instances sent), one local CA and certificate
(clan vars `odoo-local-ca`, `odoo-tls`; `trustCertificate` makes the
machine's Firefox and Chromium/Chrome trust the CA through enterprise
policies), one admin and one master
password (`odoo-passwords`). Odoo and Mailpit bind 127.0.0.1; only nginx
faces the network, and only for exposed instances.

## Configuring

```nix
# external-systems/home, machines/<machine>/configuration.nix
{lib, secrets, ...}: let
  wifi = secrets.hosts.<machine>.links.wifi;
in {
  hostSpec.services.odoo = {
    enable = true;
    lan = {                                   # only with expose.lan
      interfaces = [wifi.interface];
      allowedClients = [secrets.networks.${wifi.network}.ipv4.cidr];
    };
    instances = {
      demo = {
        modules = ["sale_management" "crm"];  # apps at creation
        expose.lan = true;
      };
      blank = {demoData = false; expose.lan = true;};
    };
  };
}
```

Per-instance options: `demoData` (true), `modules`, `language`,
`neutralize` (true), `workers` (2), `memoryMax` ("4G"),
`limits.{memorySoft,memoryHard,timeCpu,timeReal}`, `addons`, `package`,
`port`, `expose.lan`, `expose.public.{enable,domain}`. Machine-wide:
`baseDomain`, `basePort`, `mail.*`, `lan.*`, `acme.email`, `package`,
`trustCertificate`, `provisionSecrets` + the `*File` options. The
module's option descriptions are the reference; the docs page has the
table.

- Addresses, CIDRs, interfaces and public domains come from the values
  flake (`secrets`), never literals (external-systems rules).
- Instance names: DNS labels, at most 24 characters, not `mail`.
- `modules` added later install on the next start; removed ones stay
  installed until a reset. `demoData`, `language` apply at creation.
- `expose.public` needs a real domain, DNS pointing at the machine,
  ports 80/443 forwarded, and `acme.email`; with LAN instances too,
  `lan.allowedClients` is required.

## Using

| Task | Command (on the machine) |
| --- | --- |
| list instances, state, reset copy, exposure | `odoo-reset --list` |
| back to freshly created (seconds) | `sudo odoo-reset NAME` (`--all`, `--yes`) |
| rebuild from scratch | `sudo odoo-reset --clean NAME` |
| save / restore a state | `sudo odoo-snapshot save NAME TAG`, `restore NAME TAG`, `list`, `rm` |
| clean up after removing an instance | `sudo odoo-purge`, then `sudo odoo-purge NAME` |
| hosts-file lines for LAN clients | `odoo-hosts` |
| admin password | `clan vars get <machine> odoo-passwords/admin-password` (in home's devenv shell) |

Login is `admin` on every instance. Mail the instances send lands in
Mailpit (`https://mail.odoo.localhost`), from `<name>@odoo.localhost`
when it has no sender of its own. A Windows laptop on the LAN opens
`http://<machine IP>/hosts.txt` (paste into
`C:\Windows\System32\drivers\etc\hosts`, then `ipconfig /flushdns`) and
`http://<machine IP>/ca.crt` (import into Trusted Root Certification
Authorities, Local Machine); full steps in `odoo-access.md`.

Agents run these commands only when the user asks: they change the
user's test data. Deploys (`clan machines update`) and
`clan vars generate` are the owner's; report the command.

## The start sequence (what `journalctl -u odoo-NAME` shows)

ExecStartPre steps, each idempotent, each logging a `pre-start:` line:

1. runtime config: the store config plus the master password, 0600.
2. **first start** (no `.odoo.initialized`): `--init=base,<modules>`,
   demo data and language as configured, `odoo neutralize`, then its
   blocking mail server (host `invalid`) replaced by one named `Mailpit`
   and the mail queue cron re-enabled; markers `.package` and
   `.modules`, `.golden-pending`.
3. **sync**: `.package` differs (new package or addons) → `-u all`;
   `.modules` differs → install the new apps, neutralize again.
4. as root: `.golden-pending` → save the database
   (`CREATE DATABASE ... TEMPLATE`) and files as the reset copy.
5. admin password when the secret's hash changed; `web.base.url` frozen
   for public instances.

`odoo-reset` restores the copy when its key (hash of package, addons,
demo data, modules, language, neutralize) matches, else drops it and
lets step 2 create the database again. Units restart on failure (10 s,
at most 4 times in 15 min) and are capped by `MemoryMax`.

## Changing the module

Work in external-systems/modules on a branch (its `AGENTS.md`; skills
`nix-style`, `external-systems`, `vm-tests`). Keep the shell scripts in
`_odoo/*.sh` (lib.sh first, built by `mkScript`; shellcheck runs on
each fragment through treefmt and on the whole script at build). New
behaviour gets a subtest in the VM test that owns it:

| Test | Owns |
| --- | --- |
| `odoo` | instances, HTTPS, logins, isolation, websocket, nginx reload, secrets out of the store, loopback only, crash restart, memory caps, reboots |
| `odoo-reset` | reset copy, `odoo-reset`, `odoo-snapshot`, `odoo-purge`, refusals |
| `odoo-lifecycle` | `modules`, neutralize, Mailpit, package bump and new apps (specialisation) |
| `odoo-lan` | LAN exposure, `hosts.txt`/`ca.crt` bootstrap, allow-list, DHCP address change |
| `odoo-public` | ACME (pebble), public hardening |
| `odoo-firefox` | a home-manager Firefox trusts the CA |
| `odoo-chromium` | a user-installed Chromium trusts the CA |

Run them with `vm-test <name> --remote --quiet` (each takes 10-20
minutes: database creation with demo data dominates). The fixture
`tests/fixtures/nixos.nix` turns every option on for `eval-all-enabled`.
Breaking option changes ship without shims; update home in its own PR.

Traps already hit (each was a real bug, caught by these tests):

- nginx reads the TLS key itself (`root:nginx 0440`): `LoadCredential`
  breaks `systemctl reload nginx`, which runs `nginx -t` as nginx.
- nginx `return` runs before `allow`/`deny`: a location that answers
  with `return` (`/hosts.txt`) checks the allow-list through the
  `$odoo_lan_client` geo map.
- `StartLimitBurst` counts every start: the scripts run
  `systemctl reset-failed` before a deliberate start, or a few quick
  resets lock the instance out.
- LAN and public vhosts listen on every address: binding the DHCP
  address made nginx fail at boot before the lease.

Changing `baseDomain` or `lan.domain` changes the CA's name constraints:
`clan vars generate` makes a new CA, and every LAN client must import
the new `ca.crt`.

## Debugging

| Symptom | Look at |
| --- | --- |
| instance not up | `journalctl -u odoo-NAME -b`: the last `pre-start:` line is the step that failed |
| stays down after crashes | `systemctl status odoo-NAME` (start limit); `systemctl reset-failed odoo-NAME`, start it |
| killed | `journalctl -u odoo-NAME | grep -i oom`; raise `memoryMax`, lower `workers` |
| request times out | `limits.timeCpu` / `timeReal` |
| reset takes minutes | `odoo-reset --list` shows the copy `stale` or `none`; the next reset rebuilds it |
| no mail in Mailpit | `systemctl status mailpit-odoo`; in Odoo, Settings > Technical: Emails (state and failure reason), Outgoing Mail Servers (only `Mailpit` active), the queue cron in Scheduled Actions |
| certificate warning on the machine | Firefox reads `/etc/firefox/policies/policies.json`; Chromium reads `/etc/chromium/policies/managed/odoo-ca.json` (`CACertificates`, check `chrome://policy`; Chrome: `/etc/opt/chrome/...`), not the system bundle; restart the browser after a new CA |
| certificate warning on a LAN client | the client's imported CA predates a regenerated one |
| LAN name unreachable | client hosts file has an old IP (`http://<IP>/hosts.txt` again); 403 means the client is outside `lan.allowedClients` |
| nginx kept an old certificate | `systemctl reload nginx` must succeed: the TLS key is a `root:nginx 0440` clan var, never a `LoadCredential` |
| leftovers after removing an instance | `sudo odoo-purge` |

Databases: `sudo -u postgres psql -l` lists `odoo-NAME`, `@golden` and
`@snap-*`; `sudo -u odoo-NAME psql odoo-NAME` opens one as its owner.
