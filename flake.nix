{
  description = "Installs flox on GitHub Actions for the supported platforms: GNU/Linux and macOS.";

  nixConfig.extra-substituters = [
    "https://cache.flox.dev"
    "s3://flox-cache-private"
  ];
  nixConfig.extra-trusted-public-keys = [
    "flox-cache-public-1:7F4OyH7ZCnFhcze3fJdfyXYLQw/aV7GEed86nQ7IsOs="
    "flox-cache-private-1:11kWWMbsoFjVfz0lSvRr8PRkFShcmvHDfnSGphvWKnk="
  ];

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem
      (system: let
         pkgs = nixpkgs.legacyPackages.${system};
       in
       {
         devShells.default = pkgs.mkShell {
           name = "configure-nix-action";
           packages = with pkgs; [
             nodejs_20
           ];
         };
       }
      );
}
