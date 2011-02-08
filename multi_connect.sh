#!/bin/bash
# Author: Tor E Hagemann <hagemt@rpi.edu>
# Usage: ./connect.sh host_name ...
# Connect to multiple hosts simultaneously.

TERM_COMMAND='gnome-terminal'
TAB_SWITCH=' --tab'
COMMAND_SWITCH=' --command='
COMMAND='telnet 128.213.10.109 '
TITLE_SWITCH=' --title='
TITLES=(R1 R2 R3 R4 R5 R6 FRS CAT1 CAT2 CAT3 CAT4)
TITLE_INDEX=0

for port in {2001..2012}; do
	if [ $port -ne 2008 ]; then
		TERM_COMMAND=$TERM_COMMAND$TAB_SWITCH$COMMAND_SWITCH\"$COMMAND$port\"$TITLE_SWITCH\"${TITLES[$TITLE_INDEX]}\"
		let 'TITLE_INDEX += 1'
	fi
done

bash -c "$TERM_COMMAND"
