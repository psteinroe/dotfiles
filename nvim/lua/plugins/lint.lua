return {
  "mfussenegger/nvim-lint",
  event = { "BufReadPre", "BufNewFile" },
  config = function()
    local lint = require("lint")

    lint.linters_by_ft = {
      go = { "golangcilint" },
      -- Add more as needed:
      -- python = { "pylint" },
      -- javascript = { "eslint_d" },
      -- typescript = { "eslint_d" },
    }

    -- Auto-lint on save and insert leave
    vim.api.nvim_create_autocmd({ "BufWritePost", "InsertLeave", "BufEnter" }, {
      group = vim.api.nvim_create_augroup("nvim-lint", { clear = true }),
      callback = function()
        -- Only lint if the buffer has a file
        if vim.bo.buftype == "" then
          lint.try_lint()
        end
      end,
    })
  end,
}
