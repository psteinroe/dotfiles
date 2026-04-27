return {
  "nvim-treesitter/nvim-treesitter",
  build = ":TSUpdate",
  config = function()
    local parser_install_dir = vim.fn.stdpath "data" .. "/treesitter-parsers"

    -- Keep nvim-treesitter's parsers ahead of Neovim's bundled parsers.
    -- Mixing bundled parsers with plugin queries can break markdown injections.
    vim.opt.runtimepath:prepend(parser_install_dir)

    local config = require "nvim-treesitter.configs"
    config.setup {
      parser_install_dir = parser_install_dir,
      ensure_installed = {
        "nix",
        "query",
        "markdown",
        "markdown_inline",
        "html",
        "yaml",
        "latex",
      },
      sync_install = false,
      auto_install = true,
      highlight = {
        enable = true,
        -- Setting this to true will run `:h syntax` and tree-sitter at the same time.
        -- Set this to `true` if you depend on 'syntax' being enabled (like for indentation).
        -- Using this option may slow down your editor, and you may see some duplicate highlights.
        -- Instead of true it can also be a list of languages
        additional_vim_regex_highlighting = false,
      },
      indent = {
        enable = true,
      },
    }

    -- Work around a Neovim 0.12 markdown injection crash triggered by
    -- nvim-treesitter's #set-lang-from-info-string! directive.
    vim.treesitter.query.set(
      "markdown",
      "injections",
      [[
        (fenced_code_block
          (info_string
            (language) @injection.language)
          (code_fence_content) @injection.content)

        ((html_block) @injection.content
          (#set! injection.language "html")
          (#set! injection.combined)
          (#set! injection.include-children))

        ((minus_metadata) @injection.content
          (#set! injection.language "yaml")
          (#offset! @injection.content 1 0 -1 0)
          (#set! injection.include-children))

        ((plus_metadata) @injection.content
          (#set! injection.language "toml")
          (#offset! @injection.content 1 0 -1 0)
          (#set! injection.include-children))

        ([(inline) (pipe_table_cell)] @injection.content
          (#set! injection.language "markdown_inline"))

        (fenced_code_block
          (info_string (language) @lang)
          (#eq? @lang "math")
          (code_fence_content) @injection.content
          (#set! injection.language "latex"))
      ]]
    )
  end,
}
