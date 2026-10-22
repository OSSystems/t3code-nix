self:
{ lib, pkgs, ... }:
{
  programs.t3code = {
    package = lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.t3code;
    userSettings.defaultModelSelection = lib.mkDefault {
      instanceId = "claudeAgent";
      model = "claude-opus-5-5";
    };
  };
}
