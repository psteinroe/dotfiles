return {
  "nvim-treesitter/nvim-treesitter",
  branch = "main",
  lazy = false,
  build = ":TSUpdate",
  config = function()
    local install_dir = vim.fn.stdpath "data" .. "/treesitter-parsers"
    local languages = {
      "nix",
      "query",
      "markdown",
      "markdown_inline",
      "html",
      "yaml",
      "latex",
    }

    require("nvim-treesitter").setup {
      install_dir = install_dir,
    }
    require("nvim-treesitter").install(languages)

    vim.api.nvim_create_autocmd("FileType", {
      pattern = { "nix", "query", "markdown", "html", "yaml", "tex", "latex" },
      callback = function(args)
        pcall(vim.treesitter.start, args.buf)
        vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
      end,
    })

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
