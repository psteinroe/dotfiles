return {
  "nvim-neotest/neotest",
  dependencies = {
    "nvim-neotest/nvim-nio",
    "nvim-lua/plenary.nvim",
    "antoinemadec/FixCursorHold.nvim",
    "nvim-treesitter/nvim-treesitter",

    -- adapters
    "marilari88/neotest-vitest",
    "jfpedroza/neotest-elixir",


  },
  config = function()
    require("neotest").setup({
      adapters = {
          require("neotest-vitest") {
              filter_dir = function(name, rel_path, root)
                  return name ~= "node_modules"
              end,
          },
          require("neotest-elixir"),
          require('rustaceanvim.neotest')
      }
    })
  end,
}
