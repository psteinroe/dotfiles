vim.api.nvim_create_autocmd("VimEnter", {
    pattern = "*",
    callback = function()
        vim.api.nvim_out_write("check if dotenv exists \n")
        if vim.fn.exists(':Dotenv') ~= 0 then
            vim.api.nvim_out_write("loading env\n")
            vim.cmd('Dotenv! ~/.neovimenv')
        end
    end
})
