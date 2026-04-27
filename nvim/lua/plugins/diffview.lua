return {
  "dlyongemallo/diffview.nvim",
  cmd = {
    "DiffviewOpen",
    "DiffviewClose",
    "DiffviewFileHistory",
    "DiffviewDiffFiles",
  },
  init = function()
    vim.keymap.set("n", "<leader>gd", "<cmd>DiffviewOpen<CR>", { desc = "Git: Diffview open" })
    vim.keymap.set("n", "<leader>gh", "<cmd>DiffviewFileHistory %<CR>", { desc = "Git: Diffview file history" })
    vim.keymap.set("n", "<leader>gH", "<cmd>DiffviewFileHistory<CR>", { desc = "Git: Diffview repo history" })
    vim.keymap.set("n", "<leader>gq", "<cmd>DiffviewClose<CR>", { desc = "Git: Diffview close" })
  end,
}
