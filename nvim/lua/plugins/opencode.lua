return {
  "nickjvandyke/opencode.nvim",
  dependencies = {
    -- Required for snacks provider
    {
      "folke/snacks.nvim",
      opts = { input = {}, picker = {}, terminal = {} },
    },
  },
  config = function()
    local split_min_columns = 180

    local function opencode_win_for_width()
      if vim.o.columns >= split_min_columns then
        return {
          position = "right",
          width = 0.42,
          enter = true,
        }
      end

      return {
        position = "float",
        width = 0.9,
        height = 0.9,
        enter = true,
      }
    end

    local function apply_opencode_layout()
      local provider = require("opencode.config").provider
      if provider and provider.name == "snacks" then
        provider.opts.win = vim.tbl_deep_extend("force", provider.opts.win or {}, opencode_win_for_width())
      end
    end

    ---@type opencode.Opts
    vim.g.opencode_opts = {
      provider = {
        enabled = "snacks",
        snacks = {
          win = opencode_win_for_width(),
        },
      },
    }

    -- Required for opts.events.reload
    vim.o.autoread = true

    -- Ask opencode with context
    vim.keymap.set({ "n", "x" }, "<leader>oa", function()
      require("opencode").ask("@this: ", { submit = true })
    end, { desc = "Ask opencode" })

    -- Select opencode action
    vim.keymap.set({ "n", "x" }, "<leader>os", function()
      require("opencode").select()
    end, { desc = "Select opencode action" })

    -- Operator mappings
    vim.keymap.set({ "n", "x" }, "go", function()
      return require("opencode").operator "@this "
    end, { desc = "Add range to opencode", expr = true })

    vim.keymap.set("n", "goo", function()
      return require("opencode").operator "@this " .. "_"
    end, { desc = "Add line to opencode", expr = true })

    -- Scroll commands
    vim.keymap.set("n", "<S-C-u>", function()
      require("opencode").command "session.half.page.up"
    end, { desc = "Scroll opencode up" })

    vim.keymap.set("n", "<S-C-d>", function()
      require("opencode").command "session.half.page.down"
    end, { desc = "Scroll opencode down" })
  end,
}
