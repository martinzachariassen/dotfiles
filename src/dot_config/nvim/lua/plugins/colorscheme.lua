-- Catppuccin Frappé to match Ghostty / Zellij / Starship / VS Code.

return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = false,    -- load first so the scheme is ready before other plugins
    priority = 1000,
    opts = {
      flavour = "frappe",
      transparent_background = false,
      integrations = {
        cmp = true,
        gitsigns = true,
        nvimtree = true,
        treesitter = true,
        notify = true,
        mini = { enabled = true },
        which_key = true,
        telescope = { enabled = true },
        mason = true,
        markdown = true,
        native_lsp = {
          enabled = true,
          underlines = {
            errors = { "undercurl" },
            hints = { "undercurl" },
            warnings = { "undercurl" },
            information = { "undercurl" },
          },
        },
      },
    },
  },

  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "catppuccin-frappe",
    },
  },
}
