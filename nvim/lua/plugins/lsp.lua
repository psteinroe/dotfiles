return {
  {
    "williamboman/mason.nvim",
    lazy = false,
    config = function()
      require("mason").setup()
    end,
  },
  {
    "williamboman/mason-lspconfig.nvim",
    dependencies = { "williamboman/mason.nvim" },
    lazy = false,
    opts = {
      automatic_installation = true,
    },
  },
  {
    "neovim/nvim-lspconfig",
    lazy = false,
    config = function()
      -- Customize server configs if needed (merges with defaults)
      vim.lsp.config("lua_ls", {
        settings = {
          Lua = {
            diagnostics = { globals = { "vim" } },
          },
        },
      })

      -- Override postgres_lsp to use postgrestools
      vim.lsp.config("postgres_lsp", {
        cmd = { "postgrestools", "lsp-proxy" },
        filetypes = { "sql" },
        root_markers = { "postgrestools.jsonc" },
      })

      vim.lsp.config("gopls", {
        settings = {
          gopls = {
            completeUnimported = true,
            usePlaceholders = true,
            analyses = {
              unusedparams = true,
              shadow = true,
              nilness = true,
              unusedwrite = true,
              useany = true,
            },
            staticcheck = true,
            gofumpt = true,
          },
        },
      })

      -- Disable rust_analyzer from nvim-lspconfig since rustaceanvim manages it.
      -- Without this, both nvim-lspconfig and rustaceanvim would start separate
      -- rust-analyzer instances, causing duplicate LSP results (e.g., go-to-definition
      -- showing the same location twice).
      vim.lsp.config("rust_analyzer", {
        cmd = {},
        filetypes = {},
      })

      -- Enable all LSP servers (nvim-lspconfig provides the base configs)
      vim.lsp.enable({
        "lua_ls",
        "ts_ls",
        "gopls",
        "pyright",
        "eslint",
        "tailwindcss",
        "oxlint",
        "postgres_lsp",
      })

      -- Filter for React DTS (keep existing logic for gd)
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

      local function filterReactDTS(value)
        return string.match(value.filename, "react/index.d.ts") == nil
      end

      local function on_list(options)
        local items = options.items
        if #items > 1 then
          items = filter(items, filterReactDTS)
        end
        vim.fn.setqflist({}, " ", { title = options.title, items = items, context = options.context })
        if #items > 1 then
          vim.cmd("copen")
        else
          vim.cmd("cfirst")
        end
      end

      -- LspAttach autocmd for additional keymaps (0.11 defaults are used)
      -- New 0.11 defaults: grn=rename, gra=code_action, grr=references, gri=implementation, gO=symbols
      -- Also: [d/]d for diagnostics, K for hover, CTRL-S for signature help
      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(args)
          local opts = { buffer = args.buf, remap = false }
          local filetype = vim.bo[args.buf].filetype

          -- Custom gd with React DTS filter (use default for Rust)
          if filetype == "rust" then
            vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
          else
            vim.keymap.set("n", "gd", function()
              vim.lsp.buf.definition { on_list = on_list }
            end, opts)
          end

          -- Additional keymaps not covered by 0.11 defaults
          vim.keymap.set("n", "<leader>vws", vim.lsp.buf.workspace_symbol, opts)
          vim.keymap.set("n", "<leader>vd", vim.diagnostic.open_float, opts)
        end,
      })
    end,
  },
}
