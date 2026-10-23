-- Tooling (ansiblels, yamlls, pylsp, bashls, nixd, prettier, shfmt, black,
-- ruff, shellcheck, ...)

local formatters_by_ft = require("conform").formatters_by_ft
local linters_by_ft = require("lint").linters_by_ft

-- Ansible
-- Not the exrc/ansible.nvim.lua patterns verbatim: here playbooks live in
-- ansible/*.yml and task files in ansible/tasks/, with no playbooks/ or
-- roles/ directory. sdtargets/*/config.yml|manifest.yml are application
-- config, not Ansible files, so they deliberately stay plain "yaml".

vim.filetype.add({
	pattern = {
		[".*/ansible/[^/]*%.ya?ml"] = "yaml.ansible",
		[".*/ansible/tasks/.*%.ya?ml"] = "yaml.ansible",
		[".*/group_vars/.*%.ya?ml"] = "yaml.ansible",
		[".*/host_vars/.*%.ya?ml"] = "yaml.ansible",
	},
})

vim.lsp.config("ansiblels", {
	settings = {
		ansible = {
			python = {
				interpreterPath = "python3", -- nixpkgs doesn't alias plain "python" to python3
			},
		},
	},
})
vim.lsp.enable({ "ansiblels" })

-- The Quadlet/systemd templates are .j2 files. Neovim ships a jinja syntax
-- but no detector for the extension
vim.filetype.add({ extension = { j2 = "jinja" } })

-- Plain YAML (ansible/inventory, sdtargets/*/config.yml|manifest.yml): syntax
-- and duplicate-key checks only, no schema. Restricted to "yaml" so that
-- yaml.ansible is handled by ansiblels alone instead of being diagnosed by
-- two servers at once.
vim.lsp.config("yamlls", { filetypes = { "yaml" } })
vim.lsp.enable({ "yamlls" })

-- Format-on-save for YAML reuses the base config's conform autocmd.
-- versions.yml and the encrypted vault.yml are excluded in .prettierignore:
-- versions.yml is rewritten by check_updates.py --apply with ruamel at width
-- 4096, so prettier re-wrapping it would just be undone on the next apply.
formatters_by_ft.yaml = { "prettier" }
formatters_by_ft["yaml.ansible"] = { "prettier" }

-- Bash

vim.lsp.enable({ "bashls" })
require("nvim-treesitter").install({ "bash" })
formatters_by_ft.sh = { "shfmt" }
formatters_by_ft.bash = { "shfmt" }
linters_by_ft.sh = { "shellcheck" }
linters_by_ft.bash = { "shellcheck" }

-- Python
-- scripts/check_updates.py. pycodestyle/pyflakes are disabled because ruff
-- (nvim-lint, on save) is the single source of lint diagnostics; pylsp keeps
-- completion/hover/rename. No DAP/neotest: this isn't an application with a
-- test suite.

vim.lsp.config("pylsp", {
	settings = {
		pylsp = {
			plugins = {
				pycodestyle = { enabled = false },
				pyflakes = { enabled = false },
			},
		},
	},
})
vim.lsp.enable({ "pylsp" })
require("nvim-treesitter").install({ "python" })
formatters_by_ft.python = { "black" }
linters_by_ft.python = { "ruff" }

-- Nix

vim.lsp.enable({ "nixd" })
require("nvim-treesitter").install({ "nix" })
formatters_by_ft.nix = { "nixfmt" }
linters_by_ft.nix = { "statix", "deadnix" }
