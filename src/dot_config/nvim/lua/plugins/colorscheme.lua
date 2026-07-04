-- Override LazyVim's default tokyonight with Catppuccin Frappé to match
-- Ghostty / Zellij / Starship / VS Code.

return {
  -- Add the Catppuccin colorscheme plugin
  {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = false,    -- load before any other plugin so the scheme is ready
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

  -- Tell LazyVim to use it
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "catppuccin-frappe",
    },
  },
}
