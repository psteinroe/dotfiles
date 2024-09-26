return {
  "tpope/vim-fugitive",
  cmd = "Git",
  init = function()
    vim.keymap.set("n", "<Leader>gs", ":Git<CR>")
    vim.keymap.set("n", "<Leader>gc", ":Git commit | startinsert<CR>")
  end,
}
