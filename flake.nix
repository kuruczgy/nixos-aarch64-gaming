{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
  };
  outputs = { self, nixpkgs }: {
    nixosConfigurations.vm = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        ({ pkgs, modulesPath, ... }: {
          nixpkgs.overlays = [
            (final: prev: {
              qemu_kvm = prev.qemu_kvm.overrideAttrs {
                version = "9.1.50";
                src = final.fetchFromGitLab {
                  domain = "gitlab.freedesktop.org";
                  owner = "digetx";
                  repo = "qemu";
                  rev = "refs/heads/native-context-v4";
                  forceFetchGit = true;
                  postFetch = ''
                    cd $out
                    subprojects="keycodemapdb libvfio-user berkeley-softfloat-3 berkeley-testfloat-3"
                    for sp in $subprojects; do
                      ${final.meson}/bin/meson subprojects download $sp
                    done
                    rm -r subprojects/*/.git
                  '';
                  hash = "sha256-ptC7SUFzNgkRoyOEZqf6JbSGmR/VuxYLPomVf4SRbQQ=";
                };
                patches = [ ];
              };
              virglrenderer = prev.virglrenderer.overrideAttrs (old: {
                mesonFlags = old.mesonFlags ++ [
                  (nixpkgs.lib.mesonOption "drm-renderers" "msm")
                ];
              });
            })
          ];

          imports = [ (modulesPath + "/virtualisation/qemu-vm.nix") ];
          virtualisation = {
            qemu.options = [
              "-device virtio-gpu-gl,stats=off,blob=on,hostmem=32G,drm_native_context=on"
              "-display gtk,show-tabs=on,gl=on"
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
            vulkan-tools
          ];
        })
      ];
    };
    packages.aarch64-linux.qemu = self.nixosConfigurations.vm.pkgs.qemu_kvm;
    apps.aarch64-linux = {
      vm = { type = "app"; program = "${self.nixosConfigurations.vm.config.system.build.vm}/bin/run-nixos-vm"; };
    };
  };
}
