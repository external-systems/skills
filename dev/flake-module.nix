# Dev partition: lint, the skill metadata gate, formatter, devShell and
# the package-skills app. A consumer of lib or packages never evaluates it.
{
  lib,
  self,
  ...
}: {
  perSystem = {pkgs, ...}: let
    tools = with pkgs; [alejandra statix deadnix];
    python = pkgs.python3.withPackages (ps: [ps.pyyaml]);
    checkSkillMetadata = "${self}/lib/check-skill-metadata.py";

    package-skills = pkgs.writeShellApplication {
      name = "package-skills";
      runtimeInputs = [pkgs.coreutils pkgs.zip python];
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

        for skill_dir in "$skills"/*; do
          if [ -d "$skill_dir" ] && [ -f "$skill_dir/SKILL.md" ]; then
            skill=$(basename "$skill_dir")
            (cd "$skills" && zip -q -r "$output/$skill.zip" "$skill")
          fi
        done

        printf 'Created skill archives in %s\n' "$output"
      '';
    };
  in {
    formatter = pkgs.alejandra;

    devShells.default = pkgs.mkShellNoCC {packages = tools ++ [python];};

    apps.package-skills = {
      type = "app";
      program = lib.getExe package-skills;
      meta.description = "Package each skill directory into its own ZIP archive";
    };

    checks = {
      # Lint gate: alejandra (format), statix (anti-patterns), deadnix
      # (dead bindings). Source filtered to .nix files so skill edits
      # don't invalidate it.
      lint = pkgs.runCommand "lint" {nativeBuildInputs = tools;} ''
        cd ${lib.sources.sourceFilesBySuffices self [".nix"]}
        alejandra --check --quiet .
        statix check .
        deadnix --fail .
        touch $out
      '';

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
      inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) hosts sandbox;

      package-skills = pkgs.runCommand "package-skills" {} ''
        ${lib.getExe package-skills} "$TMPDIR/out"
        test -f "$TMPDIR/out/nix-style.zip"
        touch $out
      '';
    };
  };
}
