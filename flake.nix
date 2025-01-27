{
  description = "plutarch";

  nixConfig = {
    extra-experimental-features = [ "nix-command" "flakes" ];
    extra-substituters = ["https://cache.iog.io" "https://public-plutonomicon.cachix.org" "https://mlabs.cachix.org"];
    extra-trusted-public-keys = ["hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=" "public-plutonomicon.cachix.org-1:3AKJMhCLn32gri1drGuaZmFrmnue+KkKrhhubQk/CWc="];
    allow-import-from-derivation = "true";
    bash-prompt = "\\[\\e[0m\\][\\[\\e[0;2m\\]nix \\[\\e[0;1m\\]mlabs \\[\\e[0;93m\\]\\w\\[\\e[0m\\]]\\[\\e[0m\\]$ \\[\\e[0m\\]";
  };

  inputs = {
    haskell-nix.url = "github:input-output-hk/haskell.nix?rev=fe82685f4d80240034a57b99365379a9b0557d8d";
    nixpkgs.url = "github:NixOS/nixpkgs?rev=a0a69be4b5ee63f1b5e75887a406e9194012b492";

    iohk-nix.url = "github:input-output-hk/iohk-nix";
    iohk-nix.flake = false;
    # we use sphinxcontrib-haddock input
    plutus.url = "github:input-output-hk/plutus";
    # https://github.com/input-output-hk/cardano-prelude/pull/163
    cardano-prelude.url = "github:mlabs-haskell/cardano-prelude?rev=713c7ae79a4d538fcd653c976a652913df1567b9";
    cardano-prelude.flake = false;
    cardano-base.url = "github:input-output-hk/cardano-base";
    cardano-base.flake = false;
    cardano-crypto.url = "github:input-output-hk/cardano-crypto";
    cardano-crypto.flake = false;
    cardano-ledger.url = "github:input-output-hk/cardano-ledger";
    cardano-ledger.flake = false;
    # haskell-language-server.url = "github:haskell/haskell-language-server";
    # haskell-language-server.flake = false;

    # 0.4.5 hasn't been published to Hackage...
    flat.url = "github:Quid2/flat";
    flat.flake = false;
  };

  outputs = inputs@{ self, nixpkgs, iohk-nix, haskell-nix,  ... }: rec {
    supportedSystems = [ "x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];

    perSystem = nixpkgs.lib.genAttrs supportedSystems;

    hnFor = system: (import haskell-nix.inputs.nixpkgs {
      inherit system;
      overlays = [ haskell-nix.overlay (import "${iohk-nix}/overlays/crypto") ];
    }).haskell-nix;
    pkgsFor = system: import nixpkgs { inherit system; };

    default-ghc = "ghc924";


    /*
    hlsFor' = compiler-nix-name: pkgs:
      pkgs.haskell-nix.cabalProject' {
        modules = [{
          inherit nonReinstallablePkgs;
          reinstallableLibGhc = false;
        }];
        inherit compiler-nix-name;
        src = "${inputs.haskell-language-server}";
        sha256map."https://github.com/pepeiborra/ekg-json"."7a0af7a8fd38045fd15fb13445bdcc7085325460" = "fVwKxGgM0S4Kv/4egVAAiAjV7QB5PBqMVMCfsv7otIQ=";
      };
    hlsFor = compiler-nix-name: system:
      let
        pkgs = pkgsFor system;
        oldGhc = "8107";
      in
      if (compiler-nix-name == "ghc${oldGhc}") then
        pkgs.haskell-language-server.override
          {
            supportedGhcVersions = [ oldGhc ];
          }
      else
        (hlsFor' compiler-nix-name pkgs).hsPkgs.haskell-language-server.components.exes.haskell-language-server;
    */

    modules = [
      (import ./module.nix { inherit inputs; })
      (import ./mk-hackage.nix { inherit inputs; })
    ];

    mkHaskellProject = system: args: (hnFor system).cabalProject' (modules ++ [args]);

    formatter = system: with (pkgsFor system); writeShellApplication {
      name = ",format";
      runtimeInputs = [
        nixpkgs-fmt
        haskellPackages.cabal-fmt
        haskell.packages.ghc924.fourmolu_0_8_0_0
      ];
      text = builtins.readFile ./format.sh;
    };

    # versioned
    mkHaskellFlake1 =
      { project
      }:
      let
        prjFor = system: mkHaskellProject system project;
        flkFor = system: (prjFor system).flake {};
        mk = attr: perSystem (system:
          let a = (flkFor system).${attr}; in
          { default = builtins.head (builtins.attrValues a); } // a
        );
        formatting = system: (pkgsFor system).runCommandNoCC "formatting-check"
          {
            nativeBuildInputs = [ formatter system ];
          }
          ''
            cd ${project.src}
            ,format check
            touch $out
          '';
      in
      {
        packages = mk "packages";
        checks = mk "checks" // perSystem (system: { formatting = formatting system; });
        apps = mk "apps" // perSystem (system: { format.type = "app"; format.program = "${formatter system}/bin/,format"; });
        devShells = perSystem (system: { default = (flkFor system).devShell; });
        herculesCI.ciSystems = [ "x86_64-linux" ];
        project = perSystem prjFor;
      };
  };
}
