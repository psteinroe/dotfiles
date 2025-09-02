return {
  {
    "williamboman/mason.nvim",
    version = "v1.*", -- Pin to v1.x for Neovim 0.10 compatibility
    lazy = false,
    config = function()
      require("mason").setup()
    end,
  },
  {
    "williamboman/mason-lspconfig.nvim",
    version = "v1.*", -- Pin to v1.x for Neovim 0.10 compatibility
    dependencies = {
      "williamboman/mason.nvim",
    },
    lazy = false,
    opts = {
      ensure_installed = {
        "ruff",
        "lua_ls",
        "pyright",
        "ts_ls",
        "eslint",
        "tailwindcss",
        -- "ty", -- Uncomment if you want to use ty language server
      },
      automatic_installation = true,
    },
  },
  {
    "neovim/nvim-lspconfig",
    lazy = false,
    config = function()
      local lspconfig = require "lspconfig"
      local configs = require "lspconfig.configs"
      local util = require "lspconfig.util"
      local capabilities = require("cmp_nvim_lsp").default_capabilities()

      -- lspconfig.ruff.setup {
      --   capabilities = capabilities,
      -- }
      lspconfig.lua_ls.setup {
        capabilities = capabilities,
        settings = {
          Lua = {
            diagnostics = {
              globals = { "vim" },
            },
          },
        },
      }
      lspconfig.pyright.setup {
        capabilities = capabilities,
      }
      lspconfig.ts_ls.setup {
        capabilities = capabilities,
      }
      lspconfig.eslint.setup {
        capabilities = capabilities,
      }
      lspconfig.tailwindcss.setup {
        capabilities = capabilities,
      }
      -- lspconfig.ty.setup {
      --   capabilities = capabilities,
      --   init_options = {
      --     settings = {},
      --   },
      -- }
      -- configs.ty = {
      --   default_config = {
      --     cmd = { "ty", "server" },
      --     filetypes = { "python" },
      --     root_markers = { "ty.toml", "pyproject.toml", ".git" },
      --   },
      -- }
      --
      -- lspconfig.ty.setup {}

      configs.postgres_lsp = {
        default_config = {
          name = "postgres_lsp",
          cmd = { "postgrestools", "lsp-proxy" },
          root_dir = util.root_pattern "postgrestools.jsonc",
          filetypes = { "sql" },
        },
      }

      lspconfig.postgres_lsp.setup {}

      -- vim.lsp.set_log_level "debug"

      -- rust_analyzer is being handled by rustacean

      vim.keymap.set("n", "K", vim.lsp.buf.hover, {})
      vim.keymap.set("n", "<leader>gd", vim.lsp.buf.definition, {})
      vim.keymap.set("n", "<leader>gr", vim.lsp.buf.references, {})
      vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, {})
      vim.keymap.set("n", "<space>rn", vim.lsp.buf.rename, {})

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

      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(args)
          local opts = { buffer = args.buf, remap = false }

          vim.keymap.set("n", "gd", function()
            vim.lsp.buf.definition { on_list = on_list }
          end, opts)
          vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
          vim.keymap.set("n", "<leader>vws", vim.lsp.buf.workspace_symbol, opts)
          vim.keymap.set("n", "<leader>vd", vim.diagnostic.open_float, opts)
          vim.keymap.set("n", "<leader>dn", vim.diagnostic.goto_next, opts)
          vim.keymap.set("n", "<leader>dp", vim.diagnostic.goto_prev, opts)
          vim.keymap.set("n", "<leader>vca", vim.lsp.buf.code_action, opts)
          vim.keymap.set("n", "<leader>vrr", vim.lsp.buf.references, opts)
          vim.keymap.set("n", "<leader>vrn", vim.lsp.buf.rename, opts)
          vim.keymap.set("i", "<C-h>", vim.lsp.buf.signature_help, opts)
        end,
      })
    end,
  },
}
