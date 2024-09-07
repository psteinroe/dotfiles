return {
    "ggandor/leap.nvim",
    dependencies = { "tpope/vim-repeat" },
    config = function(_, opts)
      local leap = require("leap")
      for k, v in pairs(opts) do
        leap.opts[k] = v
      end
      leap.add_default_mappings(true)
      vim.keymap.del({ "x", "o" }, "x")
      vim.keymap.del({ "x", "o" }, "X")
      vim.keymap.set("n", "s", function()
        require("leap").leap({ target_windows = { vim.api.nvim_get_current_win() } })
      end)
      vim.keymap.set("n", "S", function()
        require("leap").leap({ target_windows = { vim.api.nvim_get_current_win() }, reverse = true })
      end)
    end,
}


