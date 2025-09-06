return {
  {
    "ray-x/go.nvim",
    dependencies = {
      "ray-x/guihua.lua",
      "neovim/nvim-lspconfig",
      "nvim-treesitter/nvim-treesitter",
    },
    config = function()
      require("go").setup({
        goimports = "gopls", -- goimports command
        gofmt = "gofumpt", -- gofmt command
        tag_transform = false,
        test_dir = "",
        comment_placeholder = "   ",
        lsp_cfg = false, -- false: use your own lspconfig
        lsp_gofumpt = true, -- true: set default gofmt in gopls format to gofumpt
        lsp_diag_hdlr = true, -- hook lsp diag handler
        dap_debug = true, -- set to false to disable dap
        textobjects = true, -- enable default text objects through treesitter-textobjects
        test_runner = "go", -- one of {`go`, `richgo`, `dlv`, `ginkgo`, `gotestsum`}
        verbose_tests = true, -- set to add verbose flag to tests deprecated, see "-v" option
        run_in_floaterm = false, -- set to true to run in a float terminal
        trouble = false, -- true: use trouble to open quickfix
        luasnip = false, -- enable included luasnip snippets
      })

      -- Keymaps for Go
      vim.api.nvim_set_keymap("n", "<leader>gaj", "<cmd>GoAddTag json<cr>", { desc = "Add JSON tags" })
      vim.api.nvim_set_keymap("n", "<leader>gay", "<cmd>GoAddTag yaml<cr>", { desc = "Add YAML tags" })
      vim.api.nvim_set_keymap("n", "<leader>gat", "<cmd>GoAddTag<cr>", { desc = "Add tags" })
      vim.api.nvim_set_keymap("n", "<leader>grt", "<cmd>GoRemoveTag<cr>", { desc = "Remove tags" })
      vim.api.nvim_set_keymap("n", "<leader>gfs", "<cmd>GoFillStruct<cr>", { desc = "Fill struct" })
      vim.api.nvim_set_keymap("n", "<leader>gie", "<cmd>GoIfErr<cr>", { desc = "Add if err" })
      vim.api.nvim_set_keymap("n", "<leader>gtc", "<cmd>GoCoverage<cr>", { desc = "Test coverage" })
      vim.api.nvim_set_keymap("n", "<leader>gta", "<cmd>GoTest<cr>", { desc = "Run tests" })
      vim.api.nvim_set_keymap("n", "<leader>gtf", "<cmd>GoTestFunc<cr>", { desc = "Test function" })
      vim.api.nvim_set_keymap("n", "<leader>gtp", "<cmd>GoTestPkg<cr>", { desc = "Test package" })
    end,
    event = { "CmdlineEnter" },
    ft = { "go", "gomod" },
    build = ':lua require("go.install").update_all_sync()', -- if you need to install/update all binaries
  },
}