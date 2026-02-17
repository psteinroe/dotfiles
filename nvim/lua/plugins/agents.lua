local split_min_columns = 180

local function agent_win_for_width()
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

local state = {
  active = nil,
  terminals = nil,
}

local function get_toggleterm_terminals()
  if state.terminals then
    return state.terminals
  end

  local Terminal = require("toggleterm.terminal").Terminal

  local function create_agent_terminal(opts)
    return Terminal:new {
      cmd = opts.cmd,
      direction = "float",
      shell = "zsh --login",
      hidden = true,
      count = opts.count,
      on_open = function()
        vim.cmd "startinsert!"
      end,
      on_close = function()
        vim.cmd "startinsert!"
      end,
    }
  end

  state.terminals = {
    claude = create_agent_terminal {
      cmd = "zsh --login -i -c 'ccode'",
      count = 99,
    },
    codex = create_agent_terminal {
      cmd = "zsh --login -i -c 'ccodex'",
      count = 98,
    },
    pi = create_agent_terminal {
      cmd = "zsh --login -i -c 'cpi'",
      count = 97,
    },
  }

  return state.terminals
end

local function apply_opencode_layout()
  local provider = require("opencode.config").provider
  if provider and provider.name == "snacks" then
    provider.opts.win = vim.tbl_deep_extend("force", provider.opts.win or {}, agent_win_for_width())
  end
end

local function toggle_opencode()
  apply_opencode_layout()
  require("opencode").toggle()
end

local function opencode_is_open()
  local provider = require("opencode.config").provider
  if not (provider and provider.name == "snacks" and provider.get) then
    return false
  end

  local win = provider:get()
  return win and win.valid and win:valid() or false
end

local function close_active_if_open()
  local terminals = get_toggleterm_terminals()

  if state.active == "claude" and terminals.claude:is_open() then
    terminals.claude:toggle()
  elseif state.active == "codex" and terminals.codex:is_open() then
    terminals.codex:toggle()
  elseif state.active == "pi" and terminals.pi:is_open() then
    terminals.pi:toggle()
  elseif state.active == "opencode" and opencode_is_open() then
    toggle_opencode()
  end
end

local function select_agent()
  local terminals = get_toggleterm_terminals()

  if vim.api.nvim_get_mode().mode == "t" then
    vim.cmd.stopinsert()
  end

  if state.active == "claude" and terminals.claude:is_open() then
    terminals.claude:toggle()
    return
  end

  if state.active == "codex" and terminals.codex:is_open() then
    terminals.codex:toggle()
    return
  end

  if state.active == "pi" and terminals.pi:is_open() then
    terminals.pi:toggle()
    return
  end

  if state.active == "opencode" and opencode_is_open() then
    toggle_opencode()
    return
  end

  local choices = {
    { id = "claude", label = "Claude" },
    { id = "codex", label = "Codex" },
    { id = "pi", label = "Pi" },
    { id = "opencode", label = "OpenCode" },
  }

  vim.ui.select(choices, {
    prompt = "Assistant",
    format_item = function(item)
      return item.label
    end,
    snacks = {
      win = {
        input = {
          keys = {
            ["<c-a>"] = { "close", mode = { "n", "i" } },
          },
        },
        list = {
          keys = {
            ["<c-a>"] = { "close", mode = { "n", "x" } },
          },
        },
      },
    },
  }, function(choice)
    if not choice then
      return
    end

    if state.active and state.active ~= choice.id then
      close_active_if_open()
    end

    state.active = choice.id

    if choice.id == "claude" then
      terminals.claude:toggle()
    elseif choice.id == "codex" then
      terminals.codex:toggle()
    elseif choice.id == "pi" then
      terminals.pi:toggle()
    else
      toggle_opencode()
    end
  end)
end

return {
  "akinsho/toggleterm.nvim",
  dependencies = {
    "nickjvandyke/opencode.nvim",
  },
  keys = {
    { "<C-a>", select_agent, mode = { "n", "t" }, desc = "Select assistant" },
  },
}
