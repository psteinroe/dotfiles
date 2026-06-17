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

local function remote_title_prefix()
  if vim.env.RDEV_REMOTE_TITLE ~= "1" and not vim.env.SSH_CONNECTION and not vim.env.SSH_TTY then
    return ""
  end

  return vim.env.RDEV_TITLE_PREFIX or "🌐 "
end

local function prefixed_title(title)
  local prefix = remote_title_prefix()
  if prefix ~= "" and title:sub(1, #prefix) ~= prefix then
    return prefix .. title
  end

  return title
end

function M.update_title()
  if explicit_title then
    vim.o.titlestring = literal_title(prefixed_title(explicit_title))
    return
  end

  local cwd = vim.fn.getcwd()
  local project = vim.fn.fnamemodify(cwd, ":t")
  local icon = status and status_icons[status]
  local title = project
  if icon then
    title = icon .. " " .. project
  end
  vim.o.titlestring = literal_title(prefixed_title(title))
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
