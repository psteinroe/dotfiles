require("psteinroe.packer")
require("psteinroe.set")
require("psteinroe.remap")

local augroup = vim.api.nvim_create_augroup
local psteinroeGroup = augroup('psteinroe', {})

local autocmd = vim.api.nvim_create_autocmd
local yank_group = augroup('HighlightYank', {})

function R(name)
    require("plenary.reload").reload_module(name)
end

autocmd('TextYankPost', {
    group = yank_group,
    pattern = '*',
    callback = function()
        vim.highlight.on_yank({
            higroup = 'IncSearch',
            timeout = 40,
        })
    end,
})

autocmd({"BufWritePre"}, {
    group = psteinroeGroup,
    pattern = "*",
    command = [[%s/\s\+$//e]],
})

vim.api.nvim_create_autocmd("BufRead", {
    callback = function ()
        vim.filetype.add({
            filename = {
                [".env"] = "sh",
                [".envrc"] = "sh",
                ["*.env"] = "sh",
                ["*.envrc"] = "sh",
                [".env.local"] = "sh"
            }
        })
    end,
})

vim.g.netrw_browse_split = 0
vim.g.netrw_banner = 0
vim.g.netrw_winsize = 25
vim.opt.spelllang = 'de,en_us'
vim.opt.spell = true
