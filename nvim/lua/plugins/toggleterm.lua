return {
  "akinsho/toggleterm.nvim",
  version = "*",
  lazy = false,
  config = function()
    require("toggleterm").setup {
      -- open_mapping = [[<c-ö>]],
      open_mapping = [[<c-\>]],
      shade_terminals = false,
      -- add --login so ~/.zprofile is loaded
      -- https://vi.stackexchange.com/questions/16019/neovim-terminal-not-reading-bash-profile/16021#16021
      shell = "zsh --login",
      direction = "float",
      size = function(term)
        if term.direction == "horizontal" then
          return 15
        elseif term.direction == "vertical" then
          return vim.o.columns * 0.4
        end
      end,
    }

    -- explicitly set the keymap as backup
    vim.keymap.set("n", "<C-\\>", "<Cmd>ToggleTerm<CR>", { noremap = true, silent = true, desc = "Toggle Terminal" })
    vim.keymap.set("t", "<C-\\>", "<Cmd>ToggleTerm<CR>", { noremap = true, silent = true, desc = "Toggle Terminal" })

    vim.api.nvim_create_autocmd("TermOpen", {
      pattern = "*",
      callback = function()
        vim.keymap.set("t", "<C-v>", "<C-\\><C-n>v", { noremap = true, silent = true })
        vim.keymap.set("t", "<C-q>", "<C-\\><C-n><C-v>", { noremap = true, silent = true }) -- Alternative for block mode
      end,
    })

    -- Create a dedicated terminal for Claude Code
    local Terminal = require("toggleterm.terminal").Terminal
    local claude_term = Terminal:new {
      cmd = "zsh -c 'source ~/.dotfiles/zshrc && ccode'",
      direction = "float",
      -- add --login so ~/.zprofile is loaded
      -- https://vi.stackexchange.com/questions/16019/neovim-terminal-not-reading-bash-profile/16021#16021
      shell = "zsh --login",
      hidden = true, -- Hide from regular terminal list
      count = 99, -- Give it a specific ID far from regular terminals
      on_open = function()
        vim.cmd "startinsert!"
      end,
      on_close = function()
        vim.cmd "startinsert!"
      end,
    }

    vim.keymap.set("n", "<C-a>", function()
      claude_term:toggle()
    end, { noremap = true, silent = true, desc = "Ask Claude" })

    -- Also map in terminal mode to close it
    vim.keymap.set("t", "<C-a>", function()
      claude_term:toggle()
    end, { noremap = true, silent = true, desc = "Close Claude" })
  end,
}
