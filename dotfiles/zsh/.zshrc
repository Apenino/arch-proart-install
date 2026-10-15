export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git sudo history colored-man-pages)
source $ZSH/oh-my-zsh.sh

source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

export EDITOR=nano
export PATH="$HOME/.local/bin:$PATH"
HISTSIZE=10000
SAVEHIST=10000
alias ll='ls -lah --color=auto'
alias update='sudo pacman -Syu'
