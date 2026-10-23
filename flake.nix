{
  description = "homelab dev shell: Ansible + Quadlet stack control repo";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        # scripts/check_updates.py wants PyYAML, plus ruamel.yaml for
        # comment-preserving --apply. withPackages replaces the README's
        # venv + pip step with a pinned interpreter.
        python = pkgs.python3.withPackages (ps: [ ps.pyyaml ps.ruamel-yaml ]);
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            # Ansible (make deploy/diff/check, ansible-vault)
            ansible
            ansible-lint
            ansible-language-server
            # check_updates.py (skopeo checks image tags; it can't be pip-installed)
            python
            skopeo
            # YAML + Python/Bash language servers and formatters/linters
            # referenced by .nvim.lua
            yaml-language-server
            prettier
            python3Packages.python-lsp-server
            black
            ruff
            bash-language-server
            shellcheck
            shfmt
            # Nix (this flake itself)
            nixd
            nixfmt
            statix
            deadnix
            # Lua (.nvim.lua is Lua, and the base nvim config already enables
            # lua_ls + stylua globally)
            lua-language-server
            stylua
          ];
          shellHook = ''
            # ansible-lint/ansiblels/ansible-vault look for ansible.cfg from
            # their working directory upwards, so from the repo root they'd
            # miss ansible/ansible.cfg. direnv evaluates this shell at the
            # repo root, so $PWD is the right base.
            if [ -d "$PWD/ansible" ]; then
              export ANSIBLE_CONFIG="''${ANSIBLE_CONFIG:-$PWD/ansible/ansible.cfg}"
            fi
          '';
        };
      });
}
