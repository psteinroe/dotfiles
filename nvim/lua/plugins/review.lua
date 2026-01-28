return {
  dir = vim.fn.expand("~/Developer/review.nvim.git/main"),
  name = "review.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
  },
  config = function()
    require("review").setup({
      -- Picker: auto-detects telescope/fzf-lua, falls back to native
      picker = {
        backend = "auto",
        detailed = true,
      },
      -- Persist comments to disk
      storage = {
        enabled = true,
        auto_load = true,
        auto_save = true,
      },
    })
  end,
  cmd = { "Review", "ReviewAI", "ReviewComment" },
  keys = {
    { "<leader>ro", "<cmd>Review open<cr>", desc = "Open review" },
    { "<leader>rp", "<cmd>Review pr<cr>", desc = "Review PR" },
    { "<leader>rc", "<cmd>ReviewComment<cr>", desc = "Add comment" },
    { "<leader>ra", "<cmd>ReviewAI<cr>", desc = "Send to AI" },
  },
}
