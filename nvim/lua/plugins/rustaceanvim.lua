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

          -- Rust-specific keybindings
          vim.keymap.set("n", "<leader>ca", function()
            vim.cmd.RustLsp("codeAction")
          end, { buffer = bufnr, desc = "Rust: Code Action" })

          vim.keymap.set("n", "K", function()
            vim.cmd.RustLsp({ "hover", "actions" })
          end, { buffer = bufnr, desc = "Rust: Hover Actions" })

          -- Override Rust debugging to use integrated debugging
          vim.keymap.set("n", "<leader>rd", function()
            vim.cmd.RustLsp("debuggables")
          end, { buffer = bufnr, desc = "Rust: Debug" })

          vim.keymap.set("n", "<leader>rt", function()
            vim.cmd.RustLsp("testables")
          end, { buffer = bufnr, desc = "Rust: Debug Tests" })

          vim.keymap.set("n", "<leader>rr", function()
            vim.cmd.RustLsp("runnables")
          end, { buffer = bufnr, desc = "Rust: Run" })

          vim.keymap.set("n", "<leader>re", function()
            vim.cmd.RustLsp("explainError")
          end, { buffer = bufnr, desc = "Rust: Explain Error" })

          vim.keymap.set("n", "<leader>rc", function()
            vim.cmd.RustLsp("openCargo")
          end, { buffer = bufnr, desc = "Rust: Open Cargo.toml" })

          vim.keymap.set("n", "<leader>rp", function()
            vim.cmd.RustLsp("parentModule")
          end, { buffer = bufnr, desc = "Rust: Parent Module" })
        end,
        settings = {
          ["rust-analyzer"] = {
            checkOnSave = {
              command = "clippy",
              extraArgs = { "--no-deps" },
            },
            cargo = {
              allFeatures = true,
              loadOutDirsFromCheck = true,
              runBuildScripts = true,
            },
            procMacro = {
              enable = true,
            },
          },
        },
      },
      tools = {
        -- Force rustfmt to run even if there are errors
        executor = require("rustaceanvim.executors").termopen,
        hover_actions = {
          auto_focus = true,
        },
      },
      dap = {
        adapter = {
          type = "executable",
          command = vim.fn.stdpath("data") .. "/mason/bin/codelldb",
          name = "codelldb",
        },
      },
    }
  end,
}
