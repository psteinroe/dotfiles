return {
  "nvimtools/none-ls.nvim",
  config = function()
    local null_ls = require "null-ls"
    null_ls.setup {
      sources = {
        null_ls.builtins.formatting.stylua,
        null_ls.builtins.formatting.biome,
      },
      -- configure format on save
      on_attach = function(current_client, bufnr)
        if current_client.supports_method "textDocument/formatting" then
          vim.api.nvim_clear_autocmds { group = augroup, buffer = bufnr }
          vim.api.nvim_create_autocmd("BufWritePre", {
            group = augroup,
            buffer = bufnr,
            callback = function()
              vim.lsp.buf.format {
                filter = function(client)
                  -- only use null-ls for formatting instead of lsp server for non-Rust files
                  return client.name == "null-ls" or client.name == "rust-analyzer"
                end,
                bufnr = bufnr,
              }
            end,
          })
        end
      end,
    }
  end,
}
