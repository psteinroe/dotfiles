return {
    "vim-airline/vim-airline",
    dependencies = { 
        "vim-airline/vim-airline-themes",
        "tpope/vim-fugitive", -- Required for git branch display
    },
    init = function()
        vim.g.airline_theme = "gruvbox_material"
        -- Enable git branch display
        vim.g.airline_enable_branch = 1
        -- Enable powerline fonts if you have them
        vim.g.airline_powerline_fonts = 1
        -- Show branch name in section B
        vim.g["airline#extensions#branch#enabled"] = 1
        -- Optional: customize the branch display format
        vim.g["airline#extensions#branch#format"] = 2 -- show branch name only
    end,
}
