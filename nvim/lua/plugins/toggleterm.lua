return {
  "akinsho/toggleterm.nvim",
  config = function()
    require("toggleterm").setup {
      open_mapping = [[<C-t>]],
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

    vim.api.nvim_create_autocmd("TermOpen", {
      pattern = "*",
      callback = function()
        vim.keymap.set("t", "<C-v>", "<C-\\><C-n>v", { noremap = true, silent = true })
        vim.keymap.set("t", "<C-q>", "<C-\\><C-n><C-v>", { noremap = true, silent = true }) -- Alternative for block mode
      end,
    })
  end,
  keys = {
    { [[<C-t>]] },
  },
}
