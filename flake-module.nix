# Consumer-facing outputs: the skills tree, the external skill sources,
# the fleet presets, and the composed skills dir every agent symlinks.
{
  inputs,
  lib,
  self,
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

  # Per-source selections: ready-made externalSkills lists a user's
  # profile concatenates onto a preset, e.g.
  #   extraSources = with inputs.skills.lib.selections; fluxcd ++ terraform;
  selections = {
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
    # Shared base every home-manager user gets: this repo's skills only.
    # Users add their own picks with extraSources.
    base = [];
    # The former fleet-wide host set, for users who want all of it.
    full = anthropic ++ payloadcms ++ fluxcd ++ terraform ++ mattpocock;
    # Set baked read-only at /opt/skills in the code-agent sandbox image.
    sandbox = anthropic ++ cloudflare ++ payloadcms ++ supabase ++ fluxcd ++ terraform ++ google ++ openshell;
  };

  inherit (import ./lib/mk-skills.nix {inherit lib;}) skillSet mkSkills;
  runtimeFor = import ./lib/mk-skills-runtime.nix {inherit lib;};

  # this repo's skills/ plus a preset (default: base) plus any extra
  # sources appended after it.
  composition = {
    preset ? "base",
    extraSources ? [],
  }: {
    inherit (self.lib) customSkills;
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
    inherit sources selections externalSkills skillSet mkSkills mkSkillsTree mkSkillsRuntime;
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
