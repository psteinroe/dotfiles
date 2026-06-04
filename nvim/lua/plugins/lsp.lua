return {
  -- LSPs installed via nix (packages.nix), not Mason
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
        cmd = { "postgres-language-server", "lsp-proxy" },
        filetypes = { "sql" },
        root_markers = { "postgres-language-server.jsonc" },
      })

      -- Ensure lspconfig.util is loaded before vim.lsp.enable() uses lsp/* configs
      require "lspconfig.util"

      local function make_lsp_capabilities()
        local capabilities = vim.lsp.protocol.make_client_capabilities()
        local ok, blink = pcall(require, "blink.cmp")
        if ok then
          capabilities = blink.get_lsp_capabilities(capabilities)
        end
        return capabilities
      end

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

      -- tsgo currently registers a non-file URI watcher (`bundled:///libs/**/*`) that Neovim
      -- cannot parse as a filesystem glob. Keep tsgo, but opt out of dynamic file watching.
      local tsgo_capabilities = make_lsp_capabilities()
      tsgo_capabilities.workspace = tsgo_capabilities.workspace or {}
      tsgo_capabilities.workspace.didChangeWatchedFiles = tsgo_capabilities.workspace.didChangeWatchedFiles or {}
      tsgo_capabilities.workspace.didChangeWatchedFiles.dynamicRegistration = false
      vim.lsp.config("tsgo", {
        capabilities = tsgo_capabilities,
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
          vim.cmd "copen"
        else
          vim.cmd "cfirst"
        end
      end

      -- LspAttach autocmd for additional keymaps (0.11 defaults are used)
      -- New 0.11 defaults: grn=rename, gra=code_action, grr=references, gri=implementation, gO=symbols
      -- Also: [d/]d for diagnostics, K for hover, CTRL-S for signature help
      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(args)
          local opts = { buffer = args.buf, remap = false }
          local filetype = vim.bo[args.buf].filetype

          local function keymap_opts(desc)
            return vim.tbl_extend("force", opts, { desc = desc })
          end

          -- Custom gd with React DTS filter (use default for Rust)
          if filetype == "rust" then
            vim.keymap.set("n", "gd", vim.lsp.buf.definition, keymap_opts "LSP: go to definition")
          else
            vim.keymap.set("n", "gd", function()
              vim.lsp.buf.definition { on_list = on_list }
            end, keymap_opts "LSP: go to definition")
          end

          local typescript_clients = { tsgo = true, ts_ls = true }
          local fallback_typescript_source_actions = {
            "source.organizeImports",
            "source.removeUnusedImports",
            "source.sortImports",
            "source.fixAll",
            "source.organizeImports.ts",
            "source.addMissingImports.ts",
            "source.removeUnused.ts",
            "source.fixAll.ts",
          }

          local function add_unique(list, value)
            if not vim.tbl_contains(list, value) then
              table.insert(list, value)
            end
          end

          local function get_typescript_source_actions()
            local source_actions = {}
            local has_typescript_client = false

            for _, client in ipairs(vim.lsp.get_clients { bufnr = args.buf, method = "textDocument/codeAction" }) do
              if typescript_clients[client.name] then
                has_typescript_client = true
                local code_action_provider = client.server_capabilities.codeActionProvider
                local code_action_kinds = type(code_action_provider) == "table" and code_action_provider.codeActionKinds
                  or {}

                for _, action in ipairs(code_action_kinds) do
                  if vim.startswith(action, "source.") then
                    add_unique(source_actions, action)
                  end
                end
              end
            end

            if has_typescript_client and #source_actions == 0 then
              for _, action in ipairs(fallback_typescript_source_actions) do
                add_unique(source_actions, action)
              end
            end

            return source_actions
          end

          local function code_action()
            local source_actions = get_typescript_source_actions()
            if #source_actions == 0 then
              vim.lsp.buf.code_action()
              return
            end

            local action_kinds = { "quickfix", "refactor" }
            vim.list_extend(action_kinds, source_actions)

            -- TypeScript source actions (organize imports / fix all) only appear when
            -- explicitly requested via context.only. Fold them into the normal code-action
            -- picker so there is one LSP action binding instead of a TypeScript-only one.
            vim.lsp.buf.code_action {
              context = {
                only = action_kinds,
              },
            }
          end

          -- Override Neovim's default gra action to include tsgo source actions, and keep
          -- the existing <leader>ca muscle-memory alias. Both open the same picker.
          vim.keymap.set({ "n", "x" }, "gra", code_action, keymap_opts "LSP: code action")
          vim.keymap.set({ "n", "x" }, "<leader>ca", code_action, keymap_opts "LSP: code action")
          vim.keymap.set("n", "<leader>vws", vim.lsp.buf.workspace_symbol, keymap_opts "LSP: workspace symbol")
          vim.keymap.set("n", "<leader>vd", vim.diagnostic.open_float, keymap_opts "LSP: diagnostic float")
        end,
      })

      -- Enable all LSP servers after registering LspAttach so the initial buffer also
      -- receives custom keymaps and commands.
      vim.lsp.enable {
        "lua_ls",
        "tsgo",
        "gopls",
        "ty", -- Python (astral.sh) - install via: uv tool install ty
        "tailwindcss",
        -- "oxlint", -- Disabled: current Nix oxlint package does not provide oxc_language_server.
        "postgres_lsp",
        "nil_ls", -- Nix LSP
        "jsonls", -- JSON with $schema support
      }
    end,
  },
}
