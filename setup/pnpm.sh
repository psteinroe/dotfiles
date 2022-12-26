#!/bin/sh

pnpm setup
pnpm i -g eas-cli            # Expo Application Services
pnpm i -g vscode-langservers-extracted # VSCode Language Server used by eslint lsp
pnpm i -g eslint_d # Makes eslint the fastest linter on the planet.
pnpm i -g write-good # Naive linter for English prose
pnpm i -g sql-language-server
pnpm i -g dockerfile-language-server-nodejs # Docker ls https://github.com/rcjsuen/dockerfile-language-server-nodejs