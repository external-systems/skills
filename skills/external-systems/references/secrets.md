# Secrets: varlock and 1Password

Every secret has one home, and no secret is ever written into git, Nix
code, the Nix store, a `.env` file, a PR or terminal output.

| Secret | Home | How it is used |
|---|---|---|
| What a repo's tooling needs on a developer machine: the clan SOPS admin key, API and registry tokens, Terraform/OpenTofu variables | 1Password, owner's personal account (`my.1password.com`), vault `Personal` | varlock loads it from `.env.schema` for one command (below) |
| What a NixOS machine needs at runtime: service passwords, keys, tokens, certificates | clan vars in external-systems/home (`sops/`, `vars/`) | the `clan-core` skill; generate on a branch (home's `AGENTS.md`) |
| Addresses, interfaces, deploy targets | external-systems/secrets (values, not credentials) | `inputs.secrets.values.*` |
| What CI needs | nothing: org CI is `nix flake check` and needs no secret | private inputs use the workflow's own token |

## The repo side: `.env.schema`

A repo whose tooling needs a secret commits `.env.schema` (the
`@env-spec` format) and never a `.env` with values: `.gitignore` has
`.env`, `.env.*` and `!*.env.schema`. Values come from 1Password through the varlock
1Password plugin with desktop-app authentication, so nothing is stored
on disk and every read is approved in the 1Password app:

```env-spec
# @plugin(@varlock/1password-plugin@2.0.6)
# @initOp(allowAppAuth=true, account=my.1password.com)
# @defaultRequired=true @defaultSensitive=true
# ---

# @type=string(startsWith="AGE-SECRET-KEY")
SOPS_AGE_KEY=op(op://Personal/clan-sops-age/credential)

# @sensitive=false @type=string(startsWith="age")
SOPS_AGE_PUBLIC_KEY="age1..."
```

- Pin the plugin version and varlock itself (`bunx varlock@1.24.0`, the
  first release the 2.0 plugin accepts); bump both together.
- Public values (public keys, ids that are not secret) sit in the schema
  with `@sensitive=false`.
- Check the schema without printing values: `varlock load` shows each
  item masked and fails on a missing or invalid one.
- Editor support: modules `homeSpec.programs.vscodium.envSpec.enable`.
  Questions about varlock itself: the varlock docs MCP server
  (`homeSpec.agents.mcp.varlock-docs`).

## The shell side: scope a secret to its command

Load secrets for the one command that needs them, not into the dev
shell. An agent's shell then never holds a secret, and `fmt` or `check`
never asks 1Password for anything:

```nix
# devenv.nix: the command gets the secret, the shell does not
scripts.clan.exec = ''exec bunx varlock@1.24.0 run -- "$DEVENV_STATE/clan-cli/bin/clan" "$@"'';
```

Never `eval "$(varlock load --format shell)"` in `enterShell`, never
export a secret in `devenv.nix`, and never add a `.env` fallback.

## 1Password items

- Personal account (`--account my.1password.com`), vault `Personal`.
- Category **API Credential**: the secret in the concealed `credential`
  field, so the reference is `op://Personal/<item>/credential`. Public
  halves and notes go in plain text fields on the same item.
- Title `<tool>-<purpose>`, lowercase with hyphens (`clan-sops-age`).
- The owner creates and rotates items. Create from a file through `jq`
  and `op item create` on stdin, so the value never reaches argv or
  shell history:

```sh
jq -n --rawfile v SECRET_FILE '{title: "TOOL-PURPOSE", category: "API_CREDENTIAL",
  fields: [{id: "credential", type: "CONCEALED", label: "credential", value: ($v | rtrimstr("\n"))}]}' |
  op item create --account my.1password.com --vault Personal
```

## Agents

- Never print a secret: no `op read` to the terminal, no `cat` of a key,
  no `printenv` of a value. Check a secret by something derived from it
  (`op read ... | age-keygen -y` prints the public key) or by presence.
- Never create, edit or delete 1Password items, and never write a `.env`
  with values. Tell the owner which item and field are needed.
- A command that needs a secret triggers a 1Password approval for the
  owner; when nobody approves it, stop and report instead of working
  around it.
