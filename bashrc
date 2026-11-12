# k8s-debug shell config
[ -f /etc/bash_completion ] && . /etc/bash_completion

export PS1='\[\e[1;36m\][debug]\[\e[0m\] \h:\w \$ '
export EDITOR=vi
alias vim=vi
export HISTSIZE=5000

alias ll='ls -alF --color=auto'
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias k=kubectl
command -v kubectl >/dev/null && source <(kubectl completion bash) && complete -o default -F __start_kubectl k

# Helper: list the target container's filesystem root.
#   troot <pid>   ->  /proc/<pid>/root   (use with --target / shared PID namespace)
troot() { echo "/proc/${1:?usage: troot <pid>}/root"; }

# Show the banner once, for interactive shells only.
[ -n "$PS1" ] && [ -z "$DEBUG_MOTD_SHOWN" ] && export DEBUG_MOTD_SHOWN=1 && cat /etc/motd
