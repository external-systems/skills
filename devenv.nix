# skills' additions to the org shell (pkgs/devenv): the frontmatter
# validator's python and the package-skills app's zip.
{pkgs, ...}: {
  packages = [
    (pkgs.python3.withPackages (ps: [ps.pyyaml]))
    pkgs.zip
  ];

  scripts.check-skills = {
    exec = ''python3 lib/check-skill-metadata.py skills'';
    description = "Validate every SKILL.md frontmatter (fast, no nix)";
  };
}
