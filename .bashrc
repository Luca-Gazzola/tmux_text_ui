## Change default language: POSIX or en_US.UTF-8 ##
#LANG=en_US.UTF-8
LANG=POSIX

## Change default look for user@hostname: dir/ ##
PS1='${debian_chroot:+($debian_chroot)}'
PS1+='\[\033[01;33m\]['
PS1+='\[\033[01;35m\]\u'
PS1+='\[\033[01;30m\]@'
PS1+='\[\033[00;33m\]\h'
PS1+='\[\033[01;33m\]] '
PS1+='\[\033[01;34m\]\w \[\033[00;0m\]\$ '
export PS1


## Custom Linux Aliases ##
alias ls="ls --color"
alias ll="ls -laF --color"
alias lh="ls -aF --color"


## Custom tmux Aliases ##
alias tmux-quit="tmux kill-session"
alias tmux-new="tmux new-session"
alias split-window="tmux split-window"


## Command Overrides ##
# cd override for tmux functionality (custom file explorer)
cd()
{
	builtin cd "$@"
	
	if { [ "$TERM" = "screen" ]; }
       	then
		tmux send-keys -t 1 "normal $(pwd)" C-m
		TMUX_CURRENT_DIR=$(pwd)
	fi
}

# mv override for tmux functionality (refresh file explorer)
mv()
{
	/bin/mv "$@"

	if { [ "$TERM" = "screen" ]; }
	then
		tmux send-keys -t 1 "refresh" C-m
	fi
}

# rm override for tmux functionality (refresh file explorer)
rm()
{
	/bin/rm "$@"

	if { [ "$TERM" = "screen" ]; }
	then
		tmux send-keys -t 1 "refresh" C-m
	fi
}

# cp override for tmux functionality (refresh file explorer)
cp()
{
	/bin/cp "$@"

	if { [ "$TERM" = "screen" ]; }
	then
		tmux send-keys -t 1 "refresh" C-m
	fi
}

# scp override for tmux functionality (refresh file explorer)
scp()
{
	/usr/bin/scp "$@"

	if { [ "$TERM" = "screen" ]; }
	then
		tmux send-keys -t 1 "refresh" C-m
	fi
}

# tar override for tmux functionality (refresh file explorer)
tar()
{
	/bin/tar "$@"

	if { [ "$TERM" = "screen" ]; }
	then
		tmux send-keys -t 1 "refresh" C-m
	fi
}

# git override for tmux functionality (refresh file explorer)
git()
{
	/usr/bin/git "$@"

	if { [ "$TERM" = "screen" ]; }
	then
		tmux send-keys -t 1 "refresh" C-m
	fi
}


## Custom Functions ##
# lp temporarily "previews" the directory in the custom
# tmux file explorer depending on the sleep delay. Does
# not echo to the tmux pane that the command is called
# in
lp()
{
	local ORIGIN=$(pwd)

	if { [ "$TERM" = "screen" ]; }
	then
		tmux send-keys -t 1 "preview $(realpath "$@") $ORIGIN" C-m
	fi
}

# refresh "resets" the file explorer so that it should
# properly works. Only works in tmux
refresh()
{
	if  { [ "$TERM" = "screen" ]; }
	then
		tmux send-keys -t 1 "refresh" C-m
		tmux send-keys -t 1 "refresh" C-m
	fi
}
