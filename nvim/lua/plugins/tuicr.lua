local state = {
  terminal = nil,
  cwd = nil,
}

local function fullscreen_float_opts()
  return {
    border = "none",
    row = 0,
    col = 0,
    width = function()
      return vim.o.columns
    end,
    height = function()
      return math.max(1, vim.o.lines - vim.o.cmdheight - 1)
    end,
  }
end

local function create_tuicr_terminal(cwd)
  local Terminal = require("toggleterm.terminal").Terminal

  return Terminal:new {
    cmd = "cd " .. vim.fn.shellescape(cwd) .. " && exec tuicr",
    direction = "float",
    shell = vim.o.shell .. " --login",
    hidden = true,
    count = 98,
    close_on_exit = true,
    float_opts = fullscreen_float_opts(),
    on_open = function()
      vim.cmd "startinsert!"
    end,
    on_exit = function()
      state.terminal = nil
      state.cwd = nil
    end,
  }
end

local function open_tuicr()
  if vim.api.nvim_get_mode().mode == "t" then
    vim.cmd.stopinsert()
  end

  local cwd = vim.fn.getcwd()
  if not state.terminal or state.cwd ~= cwd then
    state.terminal = create_tuicr_terminal(cwd)
    state.cwd = cwd
  end

  state.terminal:toggle()
end

return {
  "akinsho/toggleterm.nvim",
  init = function()
    vim.api.nvim_create_user_command("Tuicr", open_tuicr, {})
  end,
  keys = {
    { "<leader>tr", open_tuicr, mode = "n", desc = "Git review with tuicr" },
  },
}
