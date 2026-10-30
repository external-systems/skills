# Runtime needs of skills that ship scripts, keyed by skill name. Each
# entry lists what the skill's scripts call so agents never spend turns
# on pip/npm installs:
#   packages — executables on PATH
#   python   — ps: [...] modules for the shared python3 env
#   node     — nodejs on PATH + runtime/npm modules on NODE_PATH
#   office   — LibreOffice (soffice); skipped when office = false
# Custom skills can instead ship skills/<name>/runtime.nix with the same
# shape ({pkgs}: {...}). checks.skills-runtime fails when a skill in a
# runtime preset ships scripts but has no entry ({} = verified, none).
{pkgs}: {
  # Anthropic
  docx = {
    packages = with pkgs; [pandoc poppler-utils];
    python = ps: with ps; [defusedxml lxml];
    node = true;
    office = true;
  };
  xlsx = {
    python = ps: with ps; [defusedxml lxml markitdown openpyxl pandas];
    office = true;
  };
  mcp-builder = {
    python = ps: with ps; [anthropic mcp];
    node = true;
  };
  # The eval loop also calls the claude CLI, installed by the agents module.
  skill-creator.python = ps: [ps.pyyaml];

  # FluxCD
  gitops-repo-audit.packages = with pkgs; [fluxcd kubectl kubernetes-helm kustomize];

  # mattpocock
  diagnosing-bugs.packages = [pkgs.curl];
  wizard.packages = [pkgs.gh];
}
