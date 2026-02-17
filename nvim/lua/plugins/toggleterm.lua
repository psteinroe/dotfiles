return {
  "akinsho/toggleterm.nvim",
  version = "*",
  lazy = false,
  config = function()
    require("toggleterm").setup {
      open_mapping = [[<c-ö>]],
      -- open_mapping = [[<c-\>]],
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
      float_opts = {
        border = "rounded",
        width = function()
          return math.floor(vim.o.columns * 0.9)
        end,
        height = function()
          return math.floor(vim.o.lines * 0.9)
        end,
      },
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
  end,
}
