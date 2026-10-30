# Consumer-facing outputs: the skills tree, the external skill sources,
# the fleet presets, and the composed skills dir every agent symlinks.
{
  inputs,
  lib,
  ...
}: let
  sources = {
    anthropic = inputs.skills-anthropic;
    cloudflare = inputs.skills-cloudflare;
    payloadcms = inputs.skills-payloadcms;
    supabase = inputs.skills-supabase;
    fluxcd = inputs.skills-fluxcd;
    terraform = inputs.skills-terraform;
    google = inputs.skills-google;
    mattpocock = inputs.skills-mattpocock;
    openshell = inputs.skills-openshell;
  };

  # This repo's skills/, grouped. Every skill belongs to exactly one
  # group (checks.own-skills-grouped); core is the shared base.
  ownGroups = {
    core = ["baton-pass" "clan-core" "devenv" "flakeparts" "import-tree" "mkdocs-reveal" "nix-style" "skills-repo"];
    fleet = ["clanservices" "declarative-runtime" "determinate" "disko" "home-manager" "lib" "vm-tests"];
    kubernetes = ["envoy-gateway" "kubenix" "openebs" "rancher-kubernetes"];
    networking = ["cilium" "frr" "ifstate"];
    infra = ["terranix"];
    sandbox = ["sandbox-environment"];
  };
  own = selectSkills: [
    {
      src = ./skills;
      skillsDir = null;
      inherit selectSkills;
    }
  ];

  # Ready-made externalSkills lists a user's profile concatenates onto a
  # preset; list this repo's groups before external sources so own
  # skills win name collisions, e.g.
  #   extraSources = with inputs.skills.lib.selections; kubernetes ++ fluxcd;
  selections =
    lib.mapAttrs (_: own) ownGroups
    // {
      # Every skill in skills/ (cilium sits in networking; kubernetes
      # users usually want networking too).
      own-all = own null;
      # Anthropic official skills, cherry-picked (anthropic-all: every one).
      anthropic = [
        {
          src = sources.anthropic;
          selectSkills = ["doc-coauthoring" "docx" "internal-comms" "mcp-builder" "skill-creator" "xlsx"];
        }
      ];
      anthropic-all = [{src = sources.anthropic;}];
      cloudflare = [{src = sources.cloudflare;}];
      payloadcms = [{src = sources.payloadcms;}];
      supabase = [{src = sources.supabase;}];
      fluxcd = [{src = sources.fluxcd;}];
      terraform = [{src = sources.terraform;}];
      # google/skills and mattpocock/skills nest skills/<category>/<name>:
      # one entry per category (leaf names are unique across categories).
      google = map (category: {
        src = sources.google;
        skillsDir = "skills/${category}";
      }) ["ads" "analytics" "cloud" "developers" "identity"];
      mattpocock = map (category: {
        src = sources.mattpocock;
        skillsDir = "skills/${category}";
      }) ["engineering" "productivity"];
      # OpenShell ships skills/ and the contributor-facing .agents/skills/.
      openshell = [
        {src = sources.openshell;}
        {
          src = sources.openshell;
          skillsDir = ".agents/skills";
        }
      ];
    };

  # External skill presets (mkSkills externalSkills lists). Among
  # externals, earlier entries win name collisions; custom skills
  # (skills/) always win. selectSkills drops unknown names silently, so
  # verify the installed set after changing a preset.
  externalSkills = with selections; {
    # Shared base every home-manager user gets. Users add their own picks
    # with extraSources.
    base = core;
    # Every own skill plus the former fleet-wide host set.
    full = own-all ++ anthropic ++ payloadcms ++ fluxcd ++ terraform ++ mattpocock;
    # Set baked read-only at /opt/skills in the code-agent sandbox image.
    sandbox = own-all ++ anthropic ++ cloudflare ++ payloadcms ++ supabase ++ fluxcd ++ terraform ++ google ++ openshell;
  };

  inherit (import ./lib/mk-skills.nix {inherit lib;}) skillSet mkSkills;
  runtimeFor = import ./lib/mk-skills-runtime.nix {inherit lib;};

  # A preset (default: base) plus any extra sources appended after it.
  composition = {
    preset ? "base",
    extraSources ? [],
  }: {
    externalSkills = externalSkills.${preset} ++ extraSources;
  };

  # Composed skills dir.
  mkSkillsTree = {pkgs, ...} @ args:
    mkSkills ({inherit pkgs;} // composition (removeAttrs args ["pkgs"]));

  # Everything the scripts of that same composition call (see
  # runtime/default.nix); pass the same preset/extraSources as the tree.
  mkSkillsRuntime = {
    pkgs,
    office ? true,
    ...
  } @ args:
    runtimeFor {
      inherit pkgs office;
      skills = skillSet (composition (removeAttrs args ["pkgs" "office"]));
    };
in {
  flake.lib = {
    customSkills = ./skills;
    inherit ownGroups sources selections externalSkills skillSet mkSkills mkSkillsTree mkSkillsRuntime;
  };

  perSystem = {pkgs, ...}: {
    packages =
      lib.genAttrs (lib.attrNames externalSkills) (preset: mkSkillsTree {inherit pkgs preset;})
      // {
        default = mkSkillsTree {inherit pkgs;};
        # Covers the full preset, so every selection it uses has its tools.
        skills-runtime = mkSkillsRuntime {
          inherit pkgs;
          preset = "full";
        };
      };
  };
}
