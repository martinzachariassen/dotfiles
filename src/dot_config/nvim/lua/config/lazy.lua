-- LazyVim bootstrap — pinned to stable, auto-clones lazy.nvim on first run.
-- Edit via: chezmoi edit ~/.config/nvim/lua/config/lazy.lua
--
-- Plugin version pinning: `defaults.version = false` below means plugins track
-- their latest commit, BUT the resolved set is pinned via lazy.nvim's lockfile,
-- which IS tracked in chezmoi (dot_config/nvim/lazy-lock.json → ~/.config/nvim/
-- lazy-lock.json). So a fresh machine gets the exact same commits, not "whatever
-- is current today".
--
-- Reproduce on a new machine:   after first launch installs plugins, run
--     :Lazy restore             # check out the commits recorded in lazy-lock.json
--
-- Bump versions deliberately:
--     :Lazy update              # update + rewrite ~/.config/nvim/lazy-lock.json
--     # test, then capture the new lock back into the repo:
--     chezmoi add ~/.config/nvim/lazy-lock.json && chezmoi cd && git commit -am …
--
-- Tradeoff: `:Lazy update`/`:Lazy sync` rewrite the live lockfile, so it shows
-- as chezmoi drift until you re-add (intended — you bump on purpose).
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
