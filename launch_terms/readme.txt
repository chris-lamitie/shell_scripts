launch_terms.sh README
Version 0.4

'launch_terms.sh' is a bash script that will launch some number of gnome-terminals, specified in a conf file, then execute commands in those terminals.

Pre-Reqs:
* In the gnome-terminal settings: Command -> "When terminal commands set their own titles:" -> "Replace initial tile" is set.
* On system that is running these scripts, add the following to ~/.bashrc:
    unset PROMPT_COMMAND
    tabtitle() { printf "\033]0;$*\007"; }
* On remote systems where terminals.conf uses ssh, add the following to ~/.bashrc:
    unset PROMPT_COMMAND

The launch_terms.sh is dependent on a 'terminals.conf' file that it reads, but it can also read other config files if
a file name is supplied via the command. e.g.: './launch_terminals.sh my-terminals.conf'

The terminals.conf file uses a specific format delimited with pipes (|) and semicolons (;).
The format is as follows:
# WORKSPACE|TERMINAL|GEOMETRY|OPTIONS|TAB_ID|DELAY|COMMANDS
Delay is in seconds, you can use decimals. For no delay, use '0'. Workspaces start counting from 0.

Field description
WORKSPACE, this is the workspace number used by x11. The workspace numbering begins with '0'.
TERMINAL, this is the name of the terminal that will be created.
GEOMETRY, this is the geometry of the terminal that will be created. (See below for how to find the geometry of a terminal)
OPTIONS, this is any options given to gnome-terminal. e.g.: --hide-menubar --zoom=1.5, etc.
TAB_ID, this indicates tabs to be created. Use tab1 even if only making one terminal with no additional tabs. 
DELAY, this is the delay for commands to run in the tab.
COMMANDS, is a semicolon (;) separated list of commands to run in sequence in the terminal or tab.

Examples:
# --- Ping1 window on workspace 0 --- ssh to a server, change dir, then run a ping command.
0|Ping1|85x20+928+52|--hide-menubar|tab1|0.5|ssh -t user@example1;cd /tmp;ping -c 5 10.71.3.10
# --- Ping2 on workspace 0 window with two tabs --- use tabtitle alias then ssh to the same server twice, change different dirs, then run ping commands.
Ping2|85x20+141+41|--hide-menubar|tab1|1.0|tabtitle "example2 /var/tmp";ssh -t user@example2;cd /var/tmp;ping -c 5 10.35.3.10
Ping2|85x20+141+41|--hide-menubar|tab2|2.5|tabtitle "example2 /tmp";ssh -t user@example2;cd /tmp;ping -c 5 10.71.3.10
# --- Monitor1 window on workspace 1 with zoom and run top on the local machine.
1|Monitor1|85x20+720+480|--zoom=1.5|tab1|0|top


HOW TO FIND THE GEOMETERY OF A TERMINAL
To find the geometry of a terminal, a 'get_term_geo.sh' script is provided. To use that script, create a gnome-terminal 
and place it where  you want it and size it as you like. Then run the script in that terminal. It will output the geometry 
of the terminal in LINESxCOLUMNS+X-offset+Y-offset that is used in terminals.conf files.

Example:
user@wkstn:~/launch_terms $ ./get_term_geo.sh 
gnome-terminal geometry for this window is: "80x24+1259+631"
user@wkstn:~/launch_terms $ 

80 is the Lines value, 24 is the columns value, 1259 is the x-offset and 631 is the y-offset of the gnome terminal window. Simply copy the value between the
double quotes into the terminal.conf file shown in the above example.
