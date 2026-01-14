bindkey -v

# Atuin handles Ctrl-R, use Alt-R for FZF as fallback
bindkey -M viins '^[r' fzf-history-widget
bindkey -M viins '^f' fzf-file-widget
bindkey -M viins '^z' fzf-cd-widget

# Tab accepts autosuggestion, Shift+Tab opens completion menu
bindkey -M viins '^I' autosuggest-accept
bindkey -M viins '^[[Z' expand-or-complete

# Right arrow completion
bindkey '^[OC' right-arrow-or-complete
bindkey '^[[C' right-arrow-or-complete

# ZLE widget for right arrow completion
function right-arrow-or-complete() {
  if [[ $CURSOR -eq ${#BUFFER} ]]; then
    zle list-choices
    zle menu-complete
  else
    zle forward-char
  fi
}
zle -N right-arrow-or-complete
