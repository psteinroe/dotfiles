return {
  "akinsho/toggleterm.nvim",
  version = "*",
  lazy = false,
  config = function()
    require("toggleterm").setup {
      -- Keep <C-ö> as an alternate keyboard-layout-friendly toggle, but make
      -- <C-\> the primary ToggleTerm mapping in normal/insert/terminal mode.
      open_mapping = { [[<c-\>]], [[<c-ö>]] },
      shade_terminals = false,
      -- Add --login so ~/.zprofile is loaded. Use Neovim's resolved shell
      -- path instead of bare "zsh"; in Neovim, bare "zsh" resolves to the
      -- Nix zsh on PATH, which can hang while /bin/zsh starts normally.
      -- https://vi.stackexchange.com/questions/16019/neovim-terminal-not-reading-bash-profile/16021#16021
      shell = vim.o.shell .. " --login",
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

    vim.api.nvim_create_autocmd("TermOpen", {
      pattern = "*",
      callback = function(event)
        vim.keymap.set("t", "<C-v>", "<C-\\><C-n>v", { buffer = event.buf, noremap = true, silent = true })
        vim.keymap.set("t", "<C-q>", "<C-\\><C-n><C-v>", { buffer = event.buf, noremap = true, silent = true }) -- Alternative for block mode
      end,
    })
  end,
}
