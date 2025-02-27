{
  description = "Minimal flake environment";

  inputs = {
    systems.url = "github:nix-systems/default";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    flake-parts.url = "github:hercules-ci/flake-parts";
    pre-commit-hooks-nix.url = "github:cachix/pre-commit-hooks.nix";
    nixos-generators = { url = "github:nix-community/nixos-generators"; inputs = { nixpkgs.follows = "nixpkgs"; }; };
  };

  outputs = inputs@{ self, nixpkgs, ... }: inputs.flake-parts.lib.mkFlake { inherit inputs; } {
    systems = import inputs.systems;
    imports = [ inputs.pre-commit-hooks-nix.flakeModule ];
    perSystem =
      { config
        # , self'
        # , inputs'
      , pkgs
        # , system
        # , lib
      , ...
      }: {
        # Per-system attributes can be defined here. The self' and inputs'
        # module parameters provide easy access to attributes of the same
        # system.

        # # This sets `pkgs` to a nixpkgs with allowUnfree option set.
        # _module.args.pkgs = import nixpkgs {
        #   inherit system;
        #   config.allowUnfree = true;
        # };

        packages = {
          imunes = pkgs.callPackage ./pkgs/imunes { };
          imunes-before-break = (pkgs.callPackage ./pkgs/imunes {
            version = "2.3.0";
            sha256 = pkgs.lib.fakeSha256;
          }).overrideAttrs {
            src = pkgs.fetchFromGitHub {
              owner = "imunes";
              repo = "imunes";
              rev = "1a9d483";
              sha256 = "sha256-hw1KSxluJdA6Jiz1VzMo5IIex4AsTjSy2GklFeRpNWE=";
            };

          };
          imunes-2-3-0 = pkgs.callPackage ./pkgs/imunes {
            version = "2.3.0";
            sha256 = "sha256-Qf5u4oHnsJLGpDPRGSYbxDICL8MWiajxFb5/FADLfqc=";
          };
        };

        pre-commit.settings.hooks = {
          deadnix.enable = true;
          nixpkgs-fmt.enable = true;
          statix.enable = true;
        };

        devShells.default = pkgs.mkShell {
          shellHook = ''
            ${config.pre-commit.installationScript}
          '';
        };

        formatter = pkgs.nixpkgs-fmt;
      };

    flake = {
      overlays.imunes = final: _prev: {
        inherit (self.packages.${final.system}) imunes imunes-2-3-0 imunes-before-break;
      };

      nixosModules = {
        default_config = {
          nix.extraOptions = "experimental-features = nix-command flakes";
        };

        graphical_environment = {
          services.xserver = {
            enable = true;
            desktopManager.gnome.enable = true;
            displayManager.gdm.enable = true;
          };
        };

        imunes = { lib, pkgs, config, ... }:
          let cfg = config.virtualisation.imunes; in {
            options = {
              virtualisation.imunes = {
                enable = lib.mkEnableOption "imunes";
                package = lib.mkPackageOption pkgs "imunes-before-break" { };
              };
            };

            config = lib.mkIf cfg.enable {
              # Include Imunes overlay
              nixpkgs.overlays = [ self.overlays.imunes ];

              # Add Imunes to packages
              environment.systemPackages = [ cfg.package ];

              # Enable Open vSwitch
              virtualisation.vswitch = { enable = true; resetOnStart = true; };

              # Enable Docker
              virtualisation.docker.enable = true;
            };
          };

        computer-networks = {
          imports = [
            self.nixosModules.default_config
            self.nixosModules.graphical_environment
            self.nixosModules.imunes
            ({ pkgs, ... }: {
              system.stateVersion = "24.11";
              users.users.user = {
                isNormalUser = true;
                extraGroups = [ "network" "networkmanager" "wheel" "docker" ];
                password = "retiunimi";
              };
              environment.systemPackages = with pkgs; [
                curl
                inetutils
                iputils
                netcat
                nmap
              ];
              virtualisation.imunes.enable = true;
              virtualisation.vmVariant.virtualisation = { memorySize = 2048; cores = 2; };

              # Virtualisation guest services
              services.qemuGuest.enable = true;
              virtualisation.vmware.guest.enable = true;
            })
          ];
        };
      };

      packages = {
        x86_64-linux.computer-networks-vm = inputs.nixos-generators.nixosGenerate {
          system = "x86_64-linux";
          modules = [ self.nixosModules.computer-networks ];
          format = "qcow-efi"
          ;
        };

        aarch64-linux.computer-networks-vm = inputs.nixos-generators.nixosGenerate {
          system = "aarch64-linux";
          modules = [ self.nixosModules.computer-networks ];
          format = "qcow-efi";
        };
      };

      nixosConfigurations = {
        computer-networks-arm64 = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = [ self.nixosModules.computer-networks ];
        };

        computer-networks = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ self.nixosModules.computer-networks ];
        };
      };
    };
  };
}
