local M = {}

M.general = {
    n = {
        [";"] = {
            ":",
            "command mode",
            opts = {
                nowait = true
            }
        }
    }
}

M.nvimtree = {
    n = {
        ["<C-n>"] = { "<cmd> NvimTreeToggle <CR>", "toggle nvimtree" },
        ["<C-f>"] = { "<cmd> Telescope <CR>", "open telescope" }
    }
}

-- more keybinds!

return M
