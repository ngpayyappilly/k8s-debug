# k8s-debug shell config. Installed as /etc/bash.bashrc so it applies whatever
# HOME / UID the pod runs the debug container with (not just root's ~/.bashrc).

# Interactive shells only (previously the guard tested $PS1, which was always
# set by this very file, so it never guarded anything).
[[ $- == *i* ]] || return 0

[ -f /etc/bash_completion ] && . /etc/bash_completion

export PS1='\[\e[1;36m\][debug]\[\e[0m\] \h:\w \$ '
export EDITOR=vi
alias vim=vi
export HISTSIZE=5000

alias ll='ls -alF --color=auto'
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias k=kubectl
# Completion is generated at image build time (see Dockerfile); running
# `kubectl completion bash` here would fork kubectl on every shell start.
_kc=/usr/share/bash-completion/completions/kubectl
[ -r "$_kc" ] && . "$_kc" && complete -o default -F __start_kubectl k
unset _kc

# Helper: list the target container's filesystem root.
#   troot <pid>   ->  /proc/<pid>/root   (use with --target / shared PID namespace)
troot() { echo "/proc/${1:?usage: troot <pid>}/root"; }

# Show the banner once per shell tree.
if [ -z "$DEBUG_MOTD_SHOWN" ]; then
  export DEBUG_MOTD_SHOWN=1
  cat /etc/motd
fi
