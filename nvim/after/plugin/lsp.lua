local lsp = require "lsp-zero"
local null_ls = require "null-ls"
local mason_null_ls = require "mason-null-ls"
local cmp = require "cmp"
local lspconfig = require "lspconfig"
local configs = require "lspconfig/configs"
local util = require "lspconfig/util"

-- vim.lsp.set_log_level("debug")

require('lspconfig.configs').postgres_lsp = {
  default_config = {
    name = 'postgres_lsp',
    cmd = {'pglsp'},
    filetypes = {'sql'},
    single_file_support = true,
    -- root_dir = util.root_pattern 'root-file.txt',
    settings = {
        ['postgres_lsp'] = {
            dbConnectionString = 'postgresql://postgres:postgres@127.0.0.1:54322/postgres',
        }
    }
  }
}

lsp.preset "recommended"

lsp.configure("postgres_lsp", {force_setup = true})

lsp.ensure_installed {
  "tsserver",
  -- "eslint",
  "rust_analyzer",
  "jedi_language_server",
  -- "sqlls",
  "tailwindcss",
  "elixirls"
}

-- Fix Undefined global 'vim'
lsp.nvim_workspace()

local cmp_select = { behavior = cmp.SelectBehavior.Select }
local cmp_mappings = lsp.defaults.cmp_mappings {
  ["<C-p>"] = cmp.mapping.select_prev_item(cmp_select),
  ["<C-n>"] = cmp.mapping.select_next_item(cmp_select),
  ["<C-y>"] = cmp.mapping.confirm { select = true },
  ["<C-Space>"] = cmp.mapping.complete(),
}

-- disable completion with tab
-- this helps with copilot setup
cmp_mappings["<Tab>"] = nil
cmp_mappings["<S-Tab>"] = nil

lsp.setup_nvim_cmp {
  mapping = cmp_mappings,
}

lsp.set_preferences {
  suggest_lsp_servers = false,
  sign_icons = {
    error = "E",
    warn = "W",
    hint = "H",
    info = "I",
  },
}

-- from https://www.reddit.com/r/neovim/comments/107g8lg/how_to_ignore_node_modules_when_using/
-- ignore react.d.ts on go to definition
local function filter(arr, fn)
  if type(arr) ~= "table" then
    return arr
  end

  local filtered = {}
  for k, v in pairs(arr) do
    if fn(v, k, arr) then
      table.insert(filtered, v)
    end
  end

  return filtered
end

-- filter react/index.d.ts
local function filterReactDTS(value)
  return string.match(value.filename, "react/index.d.ts") == nil
end

-- custom list handler
local function on_list(options)
  local items = options.items
  if #items > 1 then
    -- filter out react/index.d.ts
    items = filter(items, filterReactDTS)
  end

  vim.fn.setqflist({}, " ", { title = options.title, items = items, context = options.context })
  if #items > 1 then
    -- if more than one option, open loc list
    vim.api.nvim_command "copen"
  else
    -- else jump directly
    vim.api.nvim_command "cfirst"
  end
end

lsp.on_attach(function(client, bufnr)
  local opts = { buffer = bufnr, remap = false }

  vim.keymap.set("n", "gd", function()
    vim.lsp.buf.definition { on_list = on_list }
  end, opts)
  vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
  vim.keymap.set("n", "<leader>vws", vim.lsp.buf.workspace_symbol, opts)
  vim.keymap.set("n", "<leader>vd", vim.diagnostic.open_float, opts)
  vim.keymap.set("n", "[d", vim.diagnostic.goto_next, opts)
  vim.keymap.set("n", "]d", vim.diagnostic.goto_prev, opts)
  vim.keymap.set("n", "<leader>vca", vim.lsp.buf.code_action, opts)
  vim.keymap.set("n", "<leader>vrr", vim.lsp.buf.references, opts)
  vim.keymap.set("n", "<leader>vrn", vim.lsp.buf.rename, opts)
  vim.keymap.set("i", "<C-h>", vim.lsp.buf.signature_help, opts)
end)

lsp.setup()

vim.diagnostic.config {
  virtual_text = true,
}

local null_opts = lsp.build_options("null-ls", {
  on_attach = function(client, bufnr)
    vim.api.nvim_create_autocmd("BufWritePre", {
      desc = "Auto format before save",
      pattern = "<buffer>",
      callback = function()
        vim.lsp.buf.format {
          filter = function()
            -- only use null-ls for formatting
            return client.name == "null-ls"
          end,
          bufnr = bufnr,
        }
      end,
    })
  end,
})

null_ls.setup {
  on_attach = null_opts.on_attach,
  sources = {
    -- null_ls.builtins.formatting.pg_format,
    -- null_ls.builtins.formatting.prettierd,
    null_ls.builtins.formatting.rustfmt
  },
}

mason_null_ls.setup {
  ensure_installed = nil,
  automatic_installation = true,
  automatic_setup = false,
  handlers = {},
}

