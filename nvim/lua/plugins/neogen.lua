return {
  "danymat/neogen",
  config = true,
  keys = {
    {
      "<leader>nf",
      ":lua require('neogen').generate()<CR>",
      desc = "generate annotations",
    },
  },
}
