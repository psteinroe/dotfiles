local on_attach = require("plugins.configs.lspconfig").on_attach
local capabilities = require("plugins.configs.lspconfig").capabilities

local lspconfig = require "lspconfig"

-- available servers: https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.md
local servers = {"html", "cssls", "tsserver", "clangd", "dockerls", "elixirls", "eslint", "graphql", "gopls", "pylsp",
                 "luau_lsp"}

for _, lsp in ipairs(servers) do
    lspconfig[lsp].setup {
        on_attach = on_attach,
        capabilities = capabilities
    }
end
