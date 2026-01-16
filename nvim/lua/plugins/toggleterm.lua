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

    local Terminal = require("toggleterm.terminal").Terminal

    local function create_ai_terminal(opts)
      return Terminal:new {
        cmd = opts.cmd,
        direction = "float",
        -- add --login so ~/.zprofile is loaded
        -- https://vi.stackexchange.com/questions/16019/neovim-terminal-not-reading-bash-profile/16021#16021
        shell = "zsh --login",
        hidden = true, -- Hide from regular terminal list
        count = opts.count,
        on_open = function()
          vim.cmd "startinsert!"
        end,
        on_close = function()
          vim.cmd "startinsert!"
        end,
      }
    end

    local claude_term = create_ai_terminal {
      cmd = "zsh --login -i -c 'ccode'",
      count = 99,
    }

    local codex_term = create_ai_terminal {
      cmd = "zsh --login -i -c 'ccodex'",
      count = 98,
    }

    local ai_options = {
      { label = "Claude Code", term = claude_term },
      { label = "Codex", term = codex_term },
    }

    local active_ai_term
    local ai_picker = { win = nil, buf = nil }

    local function close_ai_picker()
      if ai_picker.win and vim.api.nvim_win_is_valid(ai_picker.win) then
        vim.api.nvim_win_close(ai_picker.win, true)
      end
      if ai_picker.buf and vim.api.nvim_buf_is_valid(ai_picker.buf) then
        vim.api.nvim_buf_delete(ai_picker.buf, { force = true })
      end
      ai_picker.win = nil
      ai_picker.buf = nil
    end

    local function select_option_by_index(index)
      local option = ai_options[index]
      if not option then
        return
      end
      close_ai_picker()
      active_ai_term = option.term
      option.term:toggle()
    end

    local function open_ai_picker()
      if ai_picker.win and vim.api.nvim_win_is_valid(ai_picker.win) then
        close_ai_picker()
        return
      end

      local buf = vim.api.nvim_create_buf(false, true)
      local labels = {}
      local max_width = 0
      for index, option in ipairs(ai_options) do
        local entry = string.format("%d. %s", index, option.label)
        labels[index] = entry
        max_width = math.max(max_width, #entry)
      end

      vim.api.nvim_buf_set_lines(buf, 0, -1, false, labels)
      vim.bo[buf].bufhidden = "wipe"
      vim.bo[buf].buftype = "nofile"
      vim.bo[buf].modifiable = false
      vim.bo[buf].swapfile = false

      local height = #labels
      local width = max_width + 2
      local opts = {
        relative = "editor",
        row = (vim.o.lines - height) / 2 - 1,
        col = (vim.o.columns - width) / 2,
        width = width,
        height = height,
        style = "minimal",
        border = "rounded",
      }

      local win = vim.api.nvim_open_win(buf, true, opts)
      vim.wo[win].cursorline = true

      local function buffer_keymap(lhs, callback)
        vim.keymap.set("n", lhs, callback, { buffer = buf, nowait = true, silent = true })
      end

      buffer_keymap("<CR>", function()
        local cursor = vim.api.nvim_win_get_cursor(win)
        select_option_by_index(cursor[1])
      end)

      buffer_keymap("<Esc>", close_ai_picker)
      buffer_keymap("q", close_ai_picker)

      for index in ipairs(ai_options) do
        buffer_keymap(tostring(index), function()
          select_option_by_index(index)
        end)
      end

      ai_picker.buf = buf
      ai_picker.win = win
    end

    local function toggle_ai_terminal()
      if ai_picker.win and vim.api.nvim_win_is_valid(ai_picker.win) then
        close_ai_picker()
        return
      end

      if active_ai_term and active_ai_term:is_open() then
        active_ai_term:toggle()
      else
        open_ai_picker()
      end
    end

    vim.keymap.set("n", "<C-a>", toggle_ai_terminal, { noremap = true, silent = true, desc = "Select AI helper" })
    vim.keymap.set("t", "<C-a>", toggle_ai_terminal, { noremap = true, silent = true, desc = "Select AI helper" })
  end,
}
