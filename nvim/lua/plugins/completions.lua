return {
  {
    "L3MON4D3/LuaSnip",
    dependencies = {
      "saadparwaiz1/cmp_luasnip",
      "rafamadriz/friendly-snippets",
    },
  },
  {
    "hrsh7th/cmp-nvim-lsp",
  },
  {
    "petertriho/cmp-git",
    dependencies = { "hrsh7th/nvim-cmp" },
    init = function()
      table.insert(require("cmp").get_config().sources, { name = "git" })
    end,
  },
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      "hrsh7th/cmp-buffer",
    },
    config = function()
      local cmp = require "cmp"
      require("luasnip.loaders.from_vscode").lazy_load()

      local cmp_select = { behavior = cmp.SelectBehavior.Select }

      -- hide copilot suggestions
      -- cmp.event:on("menu_opened", function()
      --   vim.b.copilot_suggestion_hidden = true
      -- end)
      --
      -- cmp.event:on("menu_closed", function()
      --   vim.b.copilot_suggestion_hidden = false
      -- end)

      cmp.setup {
        snippet = {
          expand = function(args)
            require("luasnip").lsp_expand(args.body)
          end,
        },
        window = {
          completion = cmp.config.window.bordered(),
          documentation = cmp.config.window.bordered(),
        },
        mapping = cmp.mapping.preset.insert {
          ["<C-p>"] = cmp.mapping.select_prev_item(cmp_select),
          ["<C-n>"] = cmp.mapping.select_next_item(cmp_select),
          ["<CR>"] = cmp.mapping.confirm { select = true },
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<Tab>"] = nil,
          ["<S-Tab>"] = nil,
          ["<C-b>"] = cmp.mapping.scroll_docs(-4),
          ["<C-f>"] = cmp.mapping.scroll_docs(4),
          -- ["<C-Space>"] = cmp.mapping.complete(),
          -- ["<C-e>"] = cmp.mapping.abort(),
          -- ["<CR>"] = cmp.mapping.confirm { select = true },
        },
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "luasnip" }, -- For luasnip users.
        }, {
          { name = "buffer" },
        }),
      }
    end,
  },
}
