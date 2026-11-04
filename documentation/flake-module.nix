# Docs settings that differ from the org defaults (pkgs flakeModules.docs).
{
  perSystem.docs = {
    repo = "skills";
    settings = {
      site_name = "external-systems skills";
      nav = [
        {Home = "index.md";}
        {"Shipping skills" = "shipping.md";}
      ];
    };
  };
}
