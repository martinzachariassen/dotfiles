-- LazyVim bootstrap — pinned to stable, auto-clones lazy.nvim on first run.
-- Edit via: chezmoi edit ~/.config/nvim/lua/config/lazy.lua
--
-- Plugin version pinning: `defaults.version = false` below means each plugin
-- tracks its latest commit, so a fresh machine gets "whatever is current today"
-- — not a reproducible set. To pin exact plugin revisions across machines,
-- commit lazy.nvim's lockfile into chezmoi (it is NOT tracked by default):
--
--     nvim                         # let plugins install on first launch
--     :Lazy sync                   # resolve + write ~/.config/nvim/lazy-lock.json
--     chezmoi add ~/.config/nvim/lazy-lock.json
--     chezmoi cd && git add . && git commit -m "chore(nvim): pin plugin lockfile"
--
-- After that, `:Lazy restore` (or a fresh install) reproduces the pinned set,
-- and you bump versions deliberately with `:Lazy update` + re-`chezmoi add`.
-- See docs/day-to-day.md → "Pinning Neovim plugins".

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({
    "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath,
  })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    -- LazyVim core + its default plugin spec
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },

    -- Backend-dev language extras. Each one pulls in LSP, treesitter,
    -- formatters, and linters for that language. Enabled to match the primary
    -- stack (Java/Kotlin + TS, with the config formats you touch daily).
    -- First `nvim` launch after enabling installs the LSP servers via Mason.
    { import = "lazyvim.plugins.extras.lang.java" },
    { import = "lazyvim.plugins.extras.lang.kotlin" },
    { import = "lazyvim.plugins.extras.lang.typescript" },
    { import = "lazyvim.plugins.extras.lang.json" },
    { import = "lazyvim.plugins.extras.lang.yaml" },
    { import = "lazyvim.plugins.extras.lang.docker" },
    -- Uncomment the rest as you need them:
    -- { import = "lazyvim.plugins.extras.lang.python" },
    -- { import = "lazyvim.plugins.extras.lang.terraform" },
    -- { import = "lazyvim.plugins.extras.lang.markdown" },

    -- Other useful extras you may want later:
    -- { import = "lazyvim.plugins.extras.dap.core" },          -- debugger
    -- { import = "lazyvim.plugins.extras.test.core" },         -- test runner
    -- { import = "lazyvim.plugins.extras.coding.copilot" },    -- GitHub Copilot
    -- { import = "lazyvim.plugins.extras.editor.harpoon2" },   -- file marks

    -- Your own plugin overrides (one file per plugin in lua/plugins/)
    { import = "plugins" },
  },

  defaults = {
    lazy = false,
    version = false, -- always use the latest git commit
  },

  install = {
    colorscheme = { "catppuccin-frappe", "tokyonight", "habamax" },
  },

  -- Periodically check for plugin updates (notifies in :Lazy UI; doesn't auto-install)
  checker = { enabled = true, notify = false },

  performance = {
    rtp = {
      disabled_plugins = {
        "gzip",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
