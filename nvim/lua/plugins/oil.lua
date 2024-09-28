return {
  "stevearc/oil.nvim",
  lazy = false,
  dependencies = { "nvim-tree/nvim-web-devicons" },
  init = function()
    vim.keymap.set("n", "<leader>pv", ":Oil<CR>")
  end,
  config = function()
    require("oil").setup {
      delete_to_trash = true,
      keymaps = {
        ["<C-s>"] = false,
        ["<C-h>"] = false,
        ["<C-t>"] = false,
        ["<C-l>"] = false,
        ["<C-r>"] = "actions.refresh",
      },
      view_options = {
        show_hidden = true,
      },
    }
  end,
}
