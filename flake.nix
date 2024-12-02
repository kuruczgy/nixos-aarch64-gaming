{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
  };
  outputs = { self, nixpkgs, home-manager }:
    let
      pkgs_x86 = import nixpkgs {
        localSystem.system = "aarch64-linux";
        crossSystem.system = "x86_64-linux";
        config.allowUnfree = true;

        overlays = [
          (final: prev: {
            steam = prev.steam.override {
              extraPreBwrapCmds = ''
                ignored+=(/run)
              '';
              extraBwrapArgs = [
                "--tmpfs /run"
                "--bind /run/user /run/user"
                "--symlink ${final.mesa.drivers} /run/opengl-driver"
                "--symlink ${final.pkgsi686Linux.mesa.drivers} /run/opengl-driver-32"
              ];
            };

            # The mesa derivation in nixpkgs makes some difficult-to-modify assumptions
            # about the drivers being built, so we also have to add some unnecessary
            # drivers to make the derivation succeed.
            mesa = (prev.mesa.override {
              galliumDrivers = [ "freedreno" "llvmpipe" ];
              vulkanDrivers = [ "freedreno" "microsoft-experimental" ];
            }).overrideAttrs (old: {
              mesonFlags = old.mesonFlags ++ [
                (final.lib.mesonEnable "gallium-vdpau" false)
                (final.lib.mesonEnable "gallium-va" false)
              ];
            });
          })
        ];
      };

      pkgs = import nixpkgs {
        localSystem.system = "aarch64-linux";
        overlays = [
          (final: prev: {
            fex-emu = final.callPackage ./packages/fex-emu.nix { };

            steam-emu = final.writeShellApplication {
              name = "steam-emu";
              text = ''
                exec ${final.fex-emu}/bin/FEXInterpreter ${pkgs_x86.steam}/bin/steam -no-cef-sandbox
              '';
            };

            virglrenderer = prev.virglrenderer.overrideAttrs (old: {
              mesonFlags = old.mesonFlags ++ [
                (nixpkgs.lib.mesonOption "drm-renderers" "msm")
              ];
            });

            qemu_kvm = prev.qemu_kvm.overrideAttrs {
              version = "9.1.50";
              src = final.fetchFromGitLab {
                domain = "gitlab.freedesktop.org";
                repo = "qemu";

                owner = "digetx";
                rev = "refs/heads/native-context-v4";
                hash = "sha256-ptC7SUFzNgkRoyOEZqf6JbSGmR/VuxYLPomVf4SRbQQ=";

                forceFetchGit = true;
                postFetch = ''
                  cd $out
                  subprojects="keycodemapdb libvfio-user berkeley-softfloat-3 berkeley-testfloat-3"
                  for sp in $subprojects; do
                    ${final.meson}/bin/meson subprojects download $sp
                  done
                  rm -r subprojects/*/.git
                '';
              };
              patches = [
                # virtio-gpu: Resource UUID
                (final.fetchpatch {
                  url = "https://gitlab.freedesktop.org/digetx/qemu/-/commit/7d4b81f9497658f86d195569c649f306e76deb53.patch";
                  hash = "sha256-aUYr2RShclZhdmZvgDoktSr2mgXEqV47+p1w8wTOLFM=";
                })
              ];
            };
          })
        ];
      };
    in
    {
      nixosConfigurations.vm = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        inherit pkgs;
        modules = [
          home-manager.nixosModules.home-manager
          ({ pkgs, modulesPath, ... }: {
            imports = [ (modulesPath + "/virtualisation/qemu-vm.nix") ];
            virtualisation = {
              memorySize = 8 * 1024;
              cores = 6;
              diskSize = 32 * 1024;
              qemu.options = [
                "-device virtio-sound"
                "-device virtio-gpu-gl,stats=off,blob=on,hostmem=32G,drm_native_context=on"
                "-display sdl,gl=on"
              ];
            };
            hardware.graphics.enable = true;
            boot.kernelPackages = pkgs.linuxPackages_latest;
            services.getty.autologinUser = "user";
            users.extraUsers.user = {
              password = "";
              group = "wheel";
              isNormalUser = true;
            };
            security.sudo = {
              enable = true;
              wheelNeedsPassword = false;
            };
            programs.bash.loginShellInit = ''trap "sudo poweroff" EXIT'';

            environment.systemPackages = with pkgs; [
              # TODO: pin the volume to 100% somehow?
              pavucontrol

              # for testing
              vulkan-tools
              kmscube
              evtest
              glxinfo
              firefox
              file
              binutils

              # steam
              steam-emu
            ];

            # Enable sound with pipewire
            security.rtkit.enable = true;
            services.pipewire = {
              enable = true;
              alsa.enable = true;
              alsa.support32Bit = true;
              pulse.enable = true;
            };

            programs.sway = {
              enable = true;
              wrapperFeatures.gtk = true;
            };
            services.dbus.enable = true;

            environment.shellAliases = {
              s = "WLR_RENDERER=vulkan WLR_NO_HARDWARE_CURSORS=1 sway";
            };

            home-manager.users.user = {
              home.stateVersion = "24.11";
              wayland.windowManager.sway = {
                enable = true;
                package = pkgs.sway;
                systemd.enable = true;
                config.modifier = "Mod1";
                # config.output."*".scale = "2";
              };
            };
          })
        ];
      };
      packages.aarch64-linux = {
        inherit (self.nixosConfigurations.vm.pkgs) qemu_kvm fex-emu;
        inherit (pkgs_x86) steam lsb-release mesa;
      };
      apps.aarch64-linux = {
        vm = { type = "app"; program = "${self.nixosConfigurations.vm.config.system.build.vm}/bin/run-nixos-vm"; };
      };
    };
}
