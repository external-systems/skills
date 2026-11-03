{
  description = "external-systems agent skills — SKILL.md tree, external skill sources, and the composed skills dir for every AI coding agent";

  inputs = {
    # Shared-input authority for the org: nixpkgs and flake-parts come
    # from the artifact flake (input org-pkgs, never `pkgs`: that name is
    # the nixpkgs package set), so consumers that already follow it lock
    # nothing new.
    org-pkgs.url = "github:external-systems/pkgs";
    nixpkgs.follows = "org-pkgs/nixpkgs";
    flake-parts.follows = "org-pkgs/flake-parts";

    # ------ External agent skill sources ------ #
    # Source-only repos (flake = false), exposed as lib.sources and
    # composed by the lib.externalSkills presets (flake-module.nix).
    # Cherry-picking happens via selectSkills.
    skills-anthropic = {
      url = "github:anthropics/skills";
      flake = false;
    };
    skills-cloudflare = {
      url = "github:cloudflare/skills";
      flake = false;
    };
    skills-payloadcms = {
      url = "github:payloadcms/skills";
      flake = false;
    };
    skills-supabase = {
      url = "github:supabase/agent-skills";
      flake = false;
    };
    skills-fluxcd = {
      url = "github:fluxcd/agent-skills";
      flake = false;
    };
    skills-terraform = {
      url = "github:antonbabenko/terraform-skill";
      flake = false;
    };
    skills-google = {
      url = "github:google/skills";
      flake = false;
    };
    skills-mattpocock = {
      url = "github:mattpocock/skills";
      flake = false;
    };
    # OpenShell source tree, used only as a skill source (skills/ and
    # .agents/skills/ both ship SKILL.md dirs). flake = false keeps its
    # package graph out of this lock; keep the tag in step with the
    # openshell input of the consuming fleet flake.
    skills-openshell = {
      url = "github:NVIDIA/OpenShell?ref=v0.1.2";
      flake = false;
    };
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      # Exposes debug.options / currentSystem.options, which nixd
      # (.vscode/settings.json) reads for flake-parts option hints.
      debug = true;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      imports = [
        # treefmt, docs and slides, lock-sync (checks, formatter, apps).
        inputs.org-pkgs.flakeModules.dev
        ./flake-module.nix
        ./checks/flake-module.nix
        ./documentation/flake-module.nix
      ];
    };
}
