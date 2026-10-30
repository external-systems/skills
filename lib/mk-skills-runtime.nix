# One buildEnv with everything the scripts of a composed skill set need,
# from the needs map (runtime/default.nix + skills/<name>/runtime.nix).
# Low meta.priority so a host's own python/node win any collision.
{lib}: {
  pkgs,
  skills,
  office ? true,
}: let
  needsMap =
    import ../runtime {inherit pkgs;}
    // lib.mapAttrs (_: path: import "${path}/runtime.nix" {inherit pkgs;})
    (lib.filterAttrs (_: path: builtins.pathExists "${path}/runtime.nix") skills);

  needs = lib.attrValues (lib.intersectAttrs skills needsMap);
  any = field: lib.any (need: need.${field} or false) needs;

  python = pkgs.python3.withPackages (ps: lib.concatMap (need: (need.python or (_: [])) ps) needs);
  nodeModules = pkgs.importNpmLock.buildNodeModules {
    npmRoot = ../runtime/npm;
    inherit (pkgs) nodejs;
  };
  withNode = any "node";
  # In the closure (not only passthru.env) so installing the runtime
  # realises the modules NODE_PATH points at.
  nodeModulesLink = pkgs.runCommand "skills-runtime-node-modules" {} ''
    mkdir -p $out/lib
    ln -s ${nodeModules}/node_modules $out/lib/node_modules
  '';
in
  pkgs.buildEnv {
    name = "skills-runtime";
    paths =
      lib.unique (lib.concatMap (need: need.packages or []) needs)
      ++ lib.optional (lib.any (need: need ? python) needs) python
      ++ lib.optionals withNode [pkgs.nodejs nodeModulesLink]
      ++ lib.optional (office && any "office") pkgs.libreoffice;
    passthru = {
      # Skill names the needs map covers (checks.skills-runtime).
      covered = lib.attrNames needsMap;
      # Session variables a consumer exports next to the package.
      env = lib.optionalAttrs withNode {NODE_PATH = "${nodeModules}/node_modules";};
    };
    meta = {
      description = "Executables and modules the installed agent skills' scripts call";
      priority = 10;
    };
  }
