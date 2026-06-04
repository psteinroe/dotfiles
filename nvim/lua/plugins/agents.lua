local state = {
  pi_terminal = nil,
  pi_cwd = nil,
}

local function create_pi_terminal(cwd)
  local Terminal = require("toggleterm.terminal").Terminal

  return Terminal:new {
    cmd = "cd " .. vim.fn.shellescape(cwd) .. " && exec " .. vim.fn.shellescape(
      vim.fn.expand "~/Developer/dotfiles/bin/cpi"
    ),
    direction = "float",
    shell = vim.o.shell .. " --login",
    hidden = true,
    count = 97,
    close_on_exit = true,
    on_open = function()
      vim.cmd "startinsert!"
    end,
  }
end

local function open_pi()
  if vim.api.nvim_get_mode().mode == "t" then
    vim.cmd.stopinsert()
  end

  local cwd = vim.fn.getcwd()
  if not state.pi_terminal or state.pi_cwd ~= cwd then
    state.pi_terminal = create_pi_terminal(cwd)
    state.pi_cwd = cwd
  end

  state.pi_terminal:toggle()
end

return {
  "akinsho/toggleterm.nvim",
  keys = {
    { "<C-a>", open_pi, mode = { "n", "t" }, desc = "Toggle Pi" },
    { "<leader>ap", open_pi, mode = { "n", "x" }, desc = "Toggle Pi" },
  },
}
