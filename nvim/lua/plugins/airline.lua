return {
    "vim-airline/vim-airline",
    dependencies = { "vim-airline/vim-airline-themes" },
    init = function()
        vim.g.airline_theme = "gruvbox_material"
    end,
}
