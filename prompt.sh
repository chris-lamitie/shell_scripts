# this is a prompt script that would be placed in /etc/profile.d/propt.sh
# This will switch color if the account has uid 0 (root)
env_promt='\[\e[32m\][Dev]\[\e[0m\] '

host_clr='\[\e[32m\]\h\[\e[0m\]\[\e[94m\] \W\[\e[0m\]'

if [ $UID = 0 ];then
export PS1="${env_promt}\[\e[31m\]\u\[\e[0m\]@${host_clr} # "
else
export PS1="${env_promt}\[\e[32m\]\u\[\e[0m\]@${host_clr} $ "
fi
