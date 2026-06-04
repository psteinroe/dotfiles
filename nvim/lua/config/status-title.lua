local M = {}

local status = nil
local explicit_title = nil

local status_icons = {
  working = "◉",
  done = "✓",
}

local function literal_title(title)
  return title:gsub("%%", "%%%%")
end

function M.update_title()
  if explicit_title then
    vim.o.titlestring = literal_title(explicit_title)
    return
  end

  local cwd = vim.fn.getcwd()
  local project = vim.fn.fnamemodify(cwd, ":t")
  local icon = status and status_icons[status]
  if icon then
    vim.o.titlestring = icon .. " " .. project
  else
    vim.o.titlestring = project
  end
end

function M.set_title(title)
  explicit_title = title
  status = nil
  M.update_title()
end

function M.set(new_status)
  explicit_title = nil
  status = new_status
  M.update_title()
end

function M.clear()
  explicit_title = nil
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
