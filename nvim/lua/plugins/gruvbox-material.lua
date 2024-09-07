return {
  "sainnhe/gruvbox-material",
  priority = 1000,
  lazy = false,
  init = function()
    vim.g.gruvbox_material_background = "hard"
    vim.g.gruvbox_material_better_performance = 1
    vim.g.gruvbox_material_disable_italic_comment = 1

    vim.cmd.colorscheme "gruvbox-material"
  end,
}
