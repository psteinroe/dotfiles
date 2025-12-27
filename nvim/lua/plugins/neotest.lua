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
    "nvim-neotest/neotest-go",
  },
  config = function()
    local opts = { noremap = true, silent = true }

    -- Run nearest test
    vim.keymap.set("n", "<leader>tn", "<cmd>lua require('neotest').run.run()<CR>", opts)
    -- Run tests
    vim.keymap.set("n", "<leader>tf", "<cmd>lua require('neotest').run.run(vim.fn.expand('%'))<CR>", opts)
    -- Run last test
    vim.keymap.set("n", "<leader>tl", "<cmd>lua require('neotest').run.run_last()<CR>", opts)

    require("neotest").setup {
      adapters = {
        require "neotest-vitest" {
          filter_dir = function(name, rel_path, root)
            return name ~= "node_modules"
          end,
          vitestCommand = "pnpm vitest",
        },
        require "neotest-elixir",
        require "rustaceanvim.neotest",
        require "neotest-go" {
          args = { "-timeout=60s" },
        },
      },
    }
  end,
}
