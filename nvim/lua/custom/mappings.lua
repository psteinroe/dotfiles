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

M.lazygit = {
    n = {
        ["<leader>gg"] = {
            ":LazyGit <CR>",
            "open lazygit",
            opts = { nowait = true }
        }
    }
}

M.trouble = {
    n = {
        ["<leader>xx"] = {
            ":TroubleToggle<CR>",
            "open trouble toggle",
            opts = { silent = true, noremap = true }
        },
        ["<leader>xw"] = {
            ":TroubleToggle workspace_diagnostics<CR>",
            "open trouble toggle for workspace_diagnostics",
            opts = { silent = true, noremap = true }
        },
        ["<leader>xd"] = {
            ":TroubleToggle document_diagnostics<CR>",
            "open trouble toggle for document_diagnostics",
            opts = { silent = true, noremap = true }
        },
        ["<leader>xl"] = {
            ":TroubleToggle loclist<CR>",
            "open trouble toggle for loclist",
            opts = { silent = true, noremap = true }
        },
        ["<leader>xq"] = {
            ":TroubleToggle quickfix<CR>",
            "open trouble toggle for quickfix",
            opts = { silent = true, noremap = true }
        },
        ["<leader>gR"] = {
            ":TroubleToggle lsp_references<CR>",
            "open trouble toggle for lsp_references",
            opts = { silent = true, noremap = true }
        }
    }
}

M.nvimtree = {
    n = {
        ["<C-n>"] = { "<cmd> NvimTreeToggle <CR>", "toggle nvimtree" },
        ["<C-f>"] = { "<cmd> Telescope <CR>", "open telescope" }
    }
}

M.undotree = {
    n = {
        ["<leader>uu"] = { "<cmd> UndotreeToggle <CR>", "toggle undotree" }
    }
}

return M
