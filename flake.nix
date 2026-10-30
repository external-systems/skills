{
  description = "external-systems agent skills — SKILL.md tree, external skill sources, and the composed skills dir for every AI coding agent";

  inputs = {
    # Shared-input authority for the org: nixpkgs and flake-parts come
    # from the artifact flake, so consumers that already follow pkgs lock
    # nothing new.
    pkgs.url = "github:external-systems/pkgs";
    nixpkgs.follows = "pkgs/nixpkgs";
    flake-parts.follows = "pkgs/flake-parts";

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
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      imports = [
        inputs.flake-parts.flakeModules.partitions
        ./flake-module.nix
      ];

      # Checks, apps, formatter and devShell are evaluated only on demand;
      # a consumer reading lib or packages never touches them.
      partitionedAttrs = {
        apps = "dev";
        checks = "dev";
        devShells = "dev";
        formatter = "dev";
      };

      partitions.dev.module = ./dev/flake-module.nix;
    };
}
