return {
  "loctvl842/monokai-pro.nvim",
  lazy = false, -- load immediately
  priority = 1000, -- make sure it loads before other plugins
  config = function()
    require("monokai-pro").setup({
      transparent_background = false,
      terminal_colors = true,
      devicons = true,
      styles = {
        comment = { italic = true },
        keyword = { italic = true },
        type = { italic = true },
        storageclass = { italic = true },
        structure = { italic = true },
        parameter = { italic = true },
        annotation = { italic = true },
        tag_attribute = { italic = true },
      },
      filter = "classic", -- classic | octagon | pro | machine | ristretto | spectrum
    })

    -- set colorscheme
    vim.cmd([[colorscheme monokai-pro]])
  end,
}
