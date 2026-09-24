# Plugin entry point for oh-my-zsh, and for any manager that loads *.plugin.zsh
# (zinit, antidote, antigen, zplug). With oh-my-zsh:
#
#   git clone https://github.com/linmontfurry/Meow-Meow_Terminal_zsh_plugin.git \
#     "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/meow-meow"
#
# then add meow-meow to plugins=(...) in ~/.zshrc.
#
# The banner for this OS is chosen here. %x names the file being sourced, which
# stays correct however the manager loads it and whatever FUNCTION_ARGZERO says.
# Other systems (BSD, Cygwin, ...) get no banner rather than a broken one.
() {
  local dir=${${(%):-%x}:A:h}
  case $OSTYPE in
    (darwin*) source "$dir/zshrcmac.sh" ;;
    (linux*)  source "$dir/zshrclinux.sh" ;;
  esac
}
