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

  # google/skills nests skills/<category>/<name>: one entry per category
  # with skillsDir at the category dir (leaf names unique across them).
  googleCategories = map (category: {
    src = sources.google;
    skillsDir = "skills/${category}";
  }) ["ads" "analytics" "cloud" "developers" "identity"];

  anthropic = {
    src = sources.anthropic;
    selectSkills = ["doc-coauthoring" "docx" "internal-comms" "mcp-builder" "skill-creator" "xlsx"];
  };

  # External skill presets (mkSkills externalSkills lists). Among
  # externals, earlier entries win name collisions; custom skills
  # (skills/) always win. selectSkills drops unknown names silently, so
  # verify the installed set after changing a preset.
  externalSkills = {
    # Fleet-wide set home-manager installs for agents on NixOS hosts.
    hosts =
      [
        anthropic
        {src = sources.payloadcms;}
        {src = sources.fluxcd;}
        {src = sources.terraform;}
      ]
      ++ map (category: {
        src = sources.mattpocock;
        skillsDir = "skills/${category}";
      }) ["engineering" "productivity"];

    # Set baked read-only at /opt/skills in the code-agent sandbox image.
    sandbox =
      [
        anthropic
        {src = sources.cloudflare;}
        {src = sources.payloadcms;}
        {src = sources.supabase;}
        {src = sources.fluxcd;}
        {src = sources.terraform;}
      ]
      ++ googleCategories
      ++ [
        {src = sources.openshell;}
        {
          src = sources.openshell;
          skillsDir = ".agents/skills";
        }
      ];
  };

  mkSkills = import ./lib/mk-skills.nix {inherit lib;};

  # Composed skills dir: this repo's skills/ plus a preset (default:
  # hosts) plus any extra sources appended after it.
  mkSkillsTree = {
    pkgs,
    preset ? "hosts",
    extraSources ? [],
  }:
    mkSkills {
      inherit pkgs;
      inherit (self.lib) customSkills;
      externalSkills = externalSkills.${preset} ++ extraSources;
    };
in {
  flake.lib = {
    customSkills = ./skills;
    inherit sources externalSkills mkSkills mkSkillsTree;
  };

  perSystem = {pkgs, ...}: {
    packages =
      lib.genAttrs ["hosts" "sandbox"] (preset: mkSkillsTree {inherit pkgs preset;})
      // {default = mkSkillsTree {inherit pkgs;};};
  };
}
