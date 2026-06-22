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

    -- Work around a Neovim 0.12 markdown injection crash triggered by
    -- legacy nvim-treesitter's #set-lang-from-info-string! directive. Set this
    -- before plugin setup so the override is still active if setup degrades.
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

    local ok, treesitter = pcall(require, "nvim-treesitter")
    local has_new_api = ok and type(treesitter.install) == "function"
    if has_new_api then
      treesitter.setup {
        install_dir = install_dir,
      }
      treesitter.install(languages)
    else
      -- Local machines can have an older lazy checkout than the lockfile. Keep
      -- startup usable long enough for :Lazy restore/sync to repair it.
      vim.opt.runtimepath:prepend(install_dir)
      local ok_configs, configs = pcall(require, "nvim-treesitter.configs")
      if ok_configs then
        configs.setup {
          parser_install_dir = install_dir,
          ensure_installed = languages,
          sync_install = false,
          auto_install = false,
        }
      end
    end

    local indentexpr = has_new_api and "v:lua.require'nvim-treesitter'.indentexpr()" or "nvim_treesitter#indent()"
    vim.api.nvim_create_autocmd("FileType", {
      pattern = { "nix", "query", "markdown", "html", "yaml", "tex", "latex" },
      callback = function(args)
        pcall(vim.treesitter.start, args.buf)
        vim.bo[args.buf].indentexpr = indentexpr
      end,
    })
  end,
}
