local M = {}

local status = nil

local status_icons = {
  working = "◉",
  done = "✓",
  waiting = "⏸",
}

function M.update_title()
  local cwd = vim.fn.getcwd()
  local project = vim.fn.fnamemodify(cwd, ":t")
  local icon = status and status_icons[status]
  if icon then
    vim.o.titlestring = icon .. " " .. project
  else
    vim.o.titlestring = project
  end
end

function M.set(new_status)
  status = new_status
  M.update_title()
end

function M.clear()
  status = nil
  M.update_title()
end

vim.api.nvim_create_autocmd("TermEnter", {
  group = vim.api.nvim_create_augroup("status_title_clear", { clear = true }),
  callback = function()
    if status and status ~= "working" then
      M.clear()
    end
  end,
})

return M
