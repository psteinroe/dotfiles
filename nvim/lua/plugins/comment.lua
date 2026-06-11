return {
  "numToStr/Comment.nvim",
  config = function()
    -- Neovim 0.12 can return (ok=true, parser=nil) from get_parser() when a
    -- parser is not installed. Comment.nvim's last upstream release assumes
    -- nil parsers throw, then emits the unhelpful warning "[Comment.nvim] nil".
    local ft = require "Comment.ft"
    local calculate = ft.calculate
    ft.calculate = function(ctx)
      local ok, parser = pcall(vim.treesitter.get_parser, vim.api.nvim_get_current_buf())
      if not ok or not parser then
        return ft.get(vim.bo.filetype, ctx.ctype)
      end
      return calculate(ctx)
    end

    require("Comment").setup {}
  end,
}
