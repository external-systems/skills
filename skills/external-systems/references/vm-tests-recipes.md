# VM test recipes

Patterns proven in external-systems/modules' Odoo tests
(`vm-tests/odoo-*.nix`, helpers in `vm-tests/_odoo-common.nix`). Copy
the shape, not the Odoo specifics.

## Node addresses and a test script that uses them

`testScript` can be a function of the nodes, and node modules get
`nodes` as an argument. Use the framework's addresses instead of
literals:

```nix
nodes.server = {nodes, ...}: {
  some.allowList = map (n: "${nodes.${n}.networking.primaryIPAddress}/32") ["server" "client"];
};
testScript = {nodes, ...}: ''
  server_ip = "${nodes.server.networking.primaryIPAddress}"
'';
```

Nodes sit on VLAN 1 (`eth1`), named after the attribute (`server`
resolves on every node).

## A client that edits its hosts file

`/etc/hosts` is a symlink into the store. Replace it with a real file,
then append, as a user would:

```python
client.succeed('cp --remove-destination "$(readlink -f /etc/hosts)" /etc/hosts')
client.succeed(f"cat >> /etc/hosts <<'EOF'\n{server_ip}  app.example.home.arpa\nEOF")
```

A client that should trust a CA it downloads keeps it out of
`security.pki` and passes it explicitly (`curl --cacert`, Python
`ssl.create_default_context(cafile=...)`), so "untrusted before the
import" can be asserted too.

## Offline ACME (Let's Encrypt) with pebble

nixpkgs ships an ACME test server and client wiring that need no
network:

```nix
nodes = {
  acme = {imports = ["${inputs.nixpkgs}/nixos/tests/common/acme/server"];};
  server = {
    imports = ["${inputs.nixpkgs}/nixos/tests/common/acme/client"];
    services.nginx.virtualHosts."app.example.test" = {
      enableACME = true;
      forceSSL = true;
    };
  };
  internet = {nodes, ...}: {
    security.pki.certificateFiles = [nodes.acme.test-support.acme.caCert];
    networking.hosts.${nodes.server.networking.primaryIPAddress} = ["app.example.test"];
  };
};
```

- The `acme` node resolves every node's `security.acme.certs` domains to
  that node, so HTTP-01 validation works without DNS.
- `caCert` only signs pebble's own API. Issued certificates chain to a
  root pebble generates per run: fetch it with
  `curl -sf https://acme.test:15000/roots/0 -o /tmp/root.pem` and verify
  with `--cacert /tmp/root.pem`.
- nginx first serves a self-signed placeholder and reloads once the
  certificate arrives; wait for lego's "Server responded with a
  certificate" in `journalctl -u acme-order-renew-<domain>`, then poll
  the client.

## Proving a browser trusts a certificate

A browser sends the HTTP request only after the TLS handshake succeeds,
so a request in the server's access log proves trust. Log the host:

```nix
services.nginx.commonHttpConfig = ''
  log_format withhost '$host "$request" "$http_user_agent"';
  access_log /var/log/nginx/access.log withhost;
  error_log /var/log/nginx/error.log info;
'';
```

```python
machine.succeed("su - alice -c " + shlex.quote(
    "timeout 180 firefox --headless --no-remote --profile /tmp/ff "
    "--screenshot /tmp/shot.png https://app.example.test/?probe=1"))
machine.succeed("grep 'probe=1' /var/log/nginx/access.log | grep Firefox >/dev/null")
```

Add a control with an untrusted certificate: run it under a short
`timeout` with `machine.execute` (it never exits), then assert the
error log shows the aborted handshake (`SSL_do_handshake() failed` or
`peer closed connection in SSL handshake`) and the access log has no
request.

## Testing a configuration change

A specialisation is the second configuration; switching to it is a
deploy:

```nix
specialisation.changed.configuration.my.option = lib.mkForce "new";
```

```python
machine.succeed("/run/current-system/specialisation/changed/bin/switch-to-configuration test >&2")
machine.wait_for_unit("my.service", timeout=600)
```

To fake a package bump, wrap the same package under a new store path:
`pkgs.symlinkJoin {name = "pkg-bumped"; paths = [pkg];}`.

## Timing assertions

Assert that a fast path stayed fast with `time.monotonic()` around the
command and a generous bound (2-3x the expected time), and check its
output names the path taken, so a slow fallback cannot pass silently.
