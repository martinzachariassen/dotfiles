-- LazyVim bootstrap. Reproducibility comes from chezmoi-tracked lazy-lock.json, not
-- version pins — see docs/day-to-day.md → "Pinning Neovim plugins".

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
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },

    -- Mason installs servers on first launch; uncomment more extras as needed.
    { import = "lazyvim.plugins.extras.lang.java" },
    { import = "lazyvim.plugins.extras.lang.kotlin" },
    { import = "lazyvim.plugins.extras.lang.typescript" },
    { import = "lazyvim.plugins.extras.lang.json" },
    { import = "lazyvim.plugins.extras.lang.yaml" },
    { import = "lazyvim.plugins.extras.lang.docker" },
    -- { import = "lazyvim.plugins.extras.lang.python" },
    -- { import = "lazyvim.plugins.extras.lang.terraform" },
    -- { import = "lazyvim.plugins.extras.lang.markdown" },
    -- { import = "lazyvim.plugins.extras.dap.core" },          -- debugger
    -- { import = "lazyvim.plugins.extras.test.core" },         -- test runner
    -- { import = "lazyvim.plugins.extras.coding.copilot" },    -- GitHub Copilot
    -- { import = "lazyvim.plugins.extras.editor.harpoon2" },   -- file marks

    -- Local overrides (one file per plugin in lua/plugins/)
    { import = "plugins" },
  },

  defaults = {
    lazy = false,
    version = false, -- track latest commit; lazy-lock.json pins the resolved set
  },

  install = {
    colorscheme = { "catppuccin-mocha", "tokyonight", "habamax" },
  },

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
