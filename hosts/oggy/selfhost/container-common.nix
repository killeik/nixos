# Keep image pull and network behavior consistent across selfhost containers.
{
  pull = "always";
  networks = [ "selfhost" ];
}
