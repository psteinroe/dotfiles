local present, null_ls = pcall(require, "null-ls")

if not present then
  return
end

local b = null_ls.builtins

local sources = {
  b.code_actions.eslint_d,

  b.formatting.prettierd,

  b.formatting.pg_format,

  b.diagnostics.write_good,

  -- Lua
  b.formatting.stylua,

  -- Shell
  b.formatting.shfmt,
  b.diagnostics.shellcheck.with {
    diagnostics_format = "#{m} [#{c}]"
  },

  b.formatting.rustfmt,

  -- Github Actions
  b.diagnostics.actionlint,

  -- elixir
  b.diagnostics.credo,

  -- python
  b.diagnostics.pylint
}

null_ls.setup {
  debug = true,
  sources = sources,
  on_attach = function()
    vim.api.nvim_create_autocmd("BufWritePost", {
      callback = function()
        vim.lsp.buf.format()
      end,
    })
  end,
}
