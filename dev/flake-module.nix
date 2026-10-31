# Dev partition: the org base (treefmt, lock-sync, docs) from pkgs, the
# skill metadata gates and the package-skills and skills-drift apps. A
# consumer of lib or packages never evaluates it.
{
  inputs,
  lib,
  self,
  ...
}: {
  imports = [
    inputs.org-pkgs.flakeModules.dev
    ../documentation/flake-module.nix
  ];

  perSystem = {
    pkgs,
    self',
    ...
  }: let
    inherit (self') packages;
    python = pkgs.python3.withPackages (ps: [ps.pyyaml]);
    checkSkillMetadata = "${self}/lib/check-skill-metadata.py";
    skillManifest = "${self}/lib/skill-manifest.py";
    rev = self.shortRev or self.dirtyShortRev or "unknown";

    package-skills = pkgs.writeShellApplication {
      name = "package-skills";
      runtimeInputs = [pkgs.coreutils python];
      text = ''
        if [ "$#" -ne 1 ]; then
          echo "Usage: package-skills OUTPUT_DIR" >&2
          exit 2
        fi

        output=$(realpath -m -- "$1")
        if [ -e "$output" ] || [ -L "$output" ]; then
          echo "package-skills: output path already exists: $output" >&2
          exit 1
        fi

        skills=${self.lib.customSkills}
        python3 ${checkSkillMetadata} "$skills"
        mkdir -p -- "$output"
        python3 -I ${skillManifest} package "$skills" "$output" ${rev}

        printf 'Created skill archives and manifest.json in %s\n' "$output"
      '';
    };

    # Repo vs claude.ai account: compares this flake's skills with a cloud
    # session's synced copy of the account (or --synced DIR) and lists the
    # ones to re-upload from package-skills.
    skills-drift = pkgs.writeShellApplication {
      name = "skills-drift";
      runtimeInputs = [python];
      text = ''
        python3 -I ${skillManifest} drift ${self.lib.customSkills} "$@"
      '';
    };
  in {
    apps.package-skills = {
      type = "app";
      program = lib.getExe package-skills;
      meta.description = "Package each skill into a claude.ai-uploadable ZIP plus manifest.json";
    };

    apps.skills-drift = {
      type = "app";
      program = lib.getExe skills-drift;
      meta.description = "List repo skills missing or stale on the claude.ai account";
    };

    checks = {
      # Formatting and lint: checks.treefmt (pkgs flakeModules.treefmt).

      # Skill frontmatter gate: pi and kimi-code parse SKILL.md frontmatter
      # with JS YAML libraries that reject ': ' (colon+space) inside an
      # unquoted plain scalar and then SILENTLY skip the skill (pi reports
      # a skill conflict, kimi logs "Skipping invalid skill"). PyYAML
      # enforces the same restriction, so this fails `nix flake check`
      # before a broken skill reaches hosts or the code-agent image. The
      # validator also rejects XML-like markup in skill metadata.
      skill-frontmatter = pkgs.runCommand "skill-frontmatter" {nativeBuildInputs = [python];} ''
        python3 ${checkSkillMetadata} ${self.lib.customSkills}
        touch $out
      '';

      # Both presets compose: every external source resolves and
      # mkSkills builds the linkFarm.
      inherit (packages) base full sandbox skills-runtime;

      # Every skill in skills/ sits in exactly one ownGroups entry, so a
      # new skill can't land unreachable from every selection.
      own-skills-grouped = let
        all = lib.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir self.lib.customSkills));
        grouped = lib.concatLists (lib.attrValues self.lib.ownGroups);
        missing = lib.subtractLists grouped all;
        dupes = lib.filter (name: lib.count (n: n == name) grouped > 1) (lib.unique grouped);
        unknown = lib.subtractLists all grouped;
      in
        pkgs.runCommand "own-skills-grouped" {} (
          if missing == [] && dupes == [] && unknown == []
          then "touch $out"
          else ''
            echo "FAIL: ungrouped: ${toString missing}; in several groups: ${toString dupes}; unknown: ${toString unknown}" >&2
            exit 1
          ''
        );

      # Runtime coverage: every skill in the full tree that ships a
      # script needs a runtime/default.nix (or skills/<name>/runtime.nix)
      # entry, so a new skill can't land without its tools and agents
      # fall back to installing them mid-session.
      skills-runtime-coverage =
        pkgs.runCommand "skills-runtime-coverage" {
          covered = pkgs.writeText "covered" (lib.concatLines packages.skills-runtime.covered);
        } ''
          status=0
          for skill in ${packages.full}/*; do
            name=$(basename "$skill")
            if [ -n "$(find -L "$skill" -type f \( -name '*.py' -o -name '*.sh' -o -name '*.js' -o -name '*.mjs' -o -name '*.ts' \) -print -quit)" ] \
              && ! grep -qxF "$name" "$covered"; then
              echo "FAIL: skill '$name' ships scripts but has no runtime entry (runtime/default.nix; {} if it needs nothing)" >&2
              status=1
            fi
          done
          if [ "$status" -ne 0 ]; then exit 1; fi
          touch $out
        '';

      # Packaged zips stay valid skills and read back as in sync, both
      # stamped (unzipped archives) and unstamped (the raw tree).
      package-skills = pkgs.runCommand "package-skills" {nativeBuildInputs = [pkgs.unzip python];} ''
        ${lib.getExe package-skills} "$TMPDIR/out"
        test -f "$TMPDIR/out/nix-style.zip"
        test -f "$TMPDIR/out/manifest.json"
        mkdir "$TMPDIR/unpacked"
        for archive in "$TMPDIR"/out/*.zip; do
          unzip -q -d "$TMPDIR/unpacked" "$archive"
        done
        python3 ${checkSkillMetadata} "$TMPDIR/unpacked"
        ${lib.getExe skills-drift} --synced "$TMPDIR/unpacked"
        ${lib.getExe skills-drift} --synced ${self.lib.customSkills}
        touch $out
      '';
    };
  };
}
