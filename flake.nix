{
  inputs = {
    nixpkgs.url = "nixpkgs/release-24.05";
    naersk.url = "github:nix-community/naersk";
    naersk.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    naersk,
  }: let
    forAllSystems = nixpkgs.lib.genAttrs ["x86_64-linux" "x86_64-darwin" "i686-linux" "aarch64-linux" "aarch64-darwin"];
  in {
    lib = forAllSystems (system: nixpkgs.legacyPackages."${system}".callPackage ./default.nix {inherit naersk;});
  };
}
