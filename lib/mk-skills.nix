# Compose skill dirs into one linkFarm (one symlink per skill), a drop-in
# for the AGENTS flake's lib.mkSkills with the same arguments and output
# name. A skill is a directory; files (README, LICENSE) are ignored.
# Custom skills win name collisions; among externals, earlier entries win.
# selectSkills drops unknown names silently.
{lib}: {
  pkgs,
  customSkills ? null,
  externalSkills ? [],
}: let
  skillsIn = dir: select: let
    names = lib.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir dir));
  in
    map (name: lib.nameValuePair name "${dir}/${name}")
    (
      if select == null
      then names
      else lib.filter (name: lib.elem name select) names
    );

  external = {
    src,
    skillsDir ? "skills",
    selectSkills ? null,
  }:
    skillsIn "${src}/${skillsDir}" selectSkills;
in
  # listToAttrs keeps the first occurrence of a name.
  pkgs.linkFarm "opencode-skills" (lib.listToAttrs (
    lib.optionals (customSkills != null) (skillsIn customSkills null)
    ++ lib.concatMap external externalSkills
  ))
