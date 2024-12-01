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
              extraPkgs = pkgs: with pkgs; [
                glxinfo
                vulkan-tools
                binutils
              ];
              extraPreBwrapCmds = ''
                ignored+=(/run)
              '';
              extraBwrapArgs =
                # let
                #   runtime-dir-overlay = final.linkFarm "runtime-dir-overlay" [
                #     { name = "opengl-driver"; path = final.mesa.drivers; }
                #     { name = "opengl-driver-32"; path = final.pkgsi686Linux.mesa.drivers; }
                #   ];
                # in
                [
                  "--tmpfs /run"
                  "--bind /run/user /run/user"
                  "--symlink ${final.mesa.drivers} /run/opengl-driver"
                  "--symlink ${final.pkgsi686Linux.mesa.drivers} /run/opengl-driver-32"
                  # "--overlay-src /run"
                  # "--overlay-src ${runtime-dir-overlay}"
                  # "--ro-overlay /run"
                  # "--ro-bind ${prev.mesa.drivers} /run/opengl-driver"
                  # "--symlink ${prev.pkgsi686Linux.mesa.drivers} /run/opengl-driver-32"
                ];
            };
          })
        ];
      };

      guest_pkgs = import nixpkgs {
        localSystem.system = "aarch64-linux";
        overlays = [
          (final: prev: {
            fex-emu = final.callPackage ./packages/fex-emu.nix { };

            hack-link-drivers = (final.writeShellApplication {
              name = "hack-link-drivers";
              text = ''
                rm /run/opengl-driver
                mkdir /run/opengl-driver
                mount --bind ${final.mesa.drivers} /run/opengl-driver
                ln -s ${pkgs_x86.pkgsi686Linux.mesa.drivers} /run/opengl-driver-32
              '';
            });

            # mesa = prev.mesa.overrideAttrs (old: {
            #   patches = old.patches ++ [
            #     (final.fetchpatch {
            #       url = "https://gitlab.freedesktop.org/mesa/mesa/-/commit/d71c63d7dfa9a46bbf8012bb7ad3262971d627de.patch";
            #       hash = "sha256-F4KSy+lTsJfTizpmDNZGOGEvfUx/MLMmjUYLLhDixjs=";
            #     })
            #     (final.fetchpatch {
            #       url = "https://gitlab.freedesktop.org/mesa/mesa/-/commit/2757fa4dca62ff50404611ca3d180defcdb80e32.patch";
            #       hash = "sha256-pH7vHRNZvSYczLY3ajtxZyG6DN37gimyZi+cI0KRdeE=";
            #     })
            #   ];
            # });
          })
        ];
      };

      host_pkgs = import nixpkgs {
        localSystem.system = "aarch64-linux";
        overlays = [
          (final: prev: {
            qemu_kvm = prev.qemu_kvm.overrideAttrs {
              version = "9.1.50";
              # version = "8.2.92";
              src = final.fetchFromGitLab {
                domain = "gitlab.freedesktop.org";
                repo = "qemu";

                owner = "digetx";
                rev = "refs/heads/native-context-v4";
                hash = "sha256-ptC7SUFzNgkRoyOEZqf6JbSGmR/VuxYLPomVf4SRbQQ=";

                # owner = "robclark";
                # rev = "refs/heads/wip";
                # hash = "sha256-sK5MUjROlVplUJtmV0mIn80vWLCgRNv9VHSW80UGrqY=";

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
                (final.fetchpatch {
                  url = "https://gitlab.freedesktop.org/digetx/qemu/-/commit/7d4b81f9497658f86d195569c649f306e76deb53.patch";
                  hash = "sha256-aUYr2RShclZhdmZvgDoktSr2mgXEqV47+p1w8wTOLFM=";
                })
              ];
            };

            virglrenderer = prev.virglrenderer.overrideAttrs (old: {
              mesonFlags = old.mesonFlags ++ [
                (nixpkgs.lib.mesonOption "drm-renderers" "msm")
              ];
            });
          })
        ];
      };
    in
    {
      nixosConfigurations.vm = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        pkgs = guest_pkgs;
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
                # "-device virtio-gpu-gl,stats=off,blob=on,hostmem=32G"
                # "-display gtk,show-tabs=on,gl=on"
                "-display sdl,gl=on"
              ];
              qemu.package = host_pkgs.qemu_kvm;
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
              vulkan-tools
              kmscube
              evtest
              pavucontrol
              glxinfo
              firefox
              file
              binutils

              # FOSS games
              # minetest
              # superTuxKart
              # openttd
              # zeroad
              # xonotic

              # fex-emu
              fex-emu
              squashfsTools

              # steam
              pkgs_x86.steam
              pkgs_x86.steam.run
              hack-link-drivers
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
