return {
  "lewis6991/gitsigns.nvim",
  config = true,
  init = function()
    vim.keymap.set("n", "<leader>gp", ":Gitsigns preview_hunk<CR>", {})
    vim.keymap.set("n", "<leader>gt", ":Gitsigns toggle_current_line_blame<CR>", {})
  end,
}
