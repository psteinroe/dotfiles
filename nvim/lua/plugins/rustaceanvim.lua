return {
  "mrcjkb/rustaceanvim",
  version = "^5", -- Recommended
  lazy = false, -- This plugin is already lazy loaded
  ft = { "rust" },
  config = function()
    vim.g.rustaceanvim = {
      server = {
        on_attach = function(client, bufnr)
          -- Setup format on save for Rust files
          local format_sync_grp = vim.api.nvim_create_augroup("RustaceanFormat", { clear = true })
          vim.api.nvim_create_autocmd("BufWritePre", {
            pattern = "*.rs",
            group = format_sync_grp,
            callback = function()
              vim.lsp.buf.format({
                async = false,
                timeout_ms = 5000,
              })
            end,
          })
        end,
        settings = {
          ["rust-analyzer"] = {
            checkOnSave = {
              command = "clippy",
              extraArgs = { "--no-deps" },
            },
          },
        },
      },
      tools = {
        -- Force rustfmt to run even if there are errors
        executor = require("rustaceanvim.executors").termopen,
      },
    }
  end,
}
