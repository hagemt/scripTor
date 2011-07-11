#!/usr/bin/env bash
# Author: Tor E Hagemann <hagemt@rpi.edu>
# Purpose: Perform automated speed tests and generate graphical results.
# Directions: Place script in a working directory and schedule @hourly cron job.
# Features:
#           Usual version information provided with -V
#           Manual configuration file generation with -c (configure) option
#           Data-file rotation with -r (rotate) option
#           Graph generation every 24 datapoints, or on demand with -g

SCRIPT_DIR="$(dirname $0)"
CONFIG_FILE="$SCRIPT_DIR/tsast.conf"
DATA_FILE="$SCRIPT_DIR/tsast.dat"
LOG_FILE="$SCRIPT_DIR/dl.log"
DATE_STRING="$($(type -p date) +%m%d%Y)"
GNUPLOT_CMD="$(type -p gnuplot)"
WGET_CMD="$(type -p wget)"
WGET_DOMAIN="cachefly.cachefly.net"
WGET_FILES=( "1mb.test" "10mb.test" "100mb.test" )
WGET_FILE_ORDER=( 0 1 0 1 0 2 0 1 0 )
WGET_PIPE="tee -a $LOG_FILE | egrep -o '[0-9.]+ KB' | cut -d ' ' -f 1"

# Produce a gnuplot configuration with label information injected
function write_conf {
	MAX_ENTRY=$(echo "$(sort -g $DATA_FILE | tail -n 1) * 1.1" | bc -l)
	echo "set title 'Tor''s Simple Automated Speed Test [${DATE_STRING:-yesterday}]'" > ${1:-$CONFIG_FILE}
	echo "set xrange [0:23]" >> ${1:-$CONFIG_FILE}
	echo "set yrange [0:$MAX_ENTRY]" >> ${1:-$CONFIG_FILE}
	echo -e "set xtics ( \\\\\n\
		'12am' 0,  ''  1, ''  2, \\\\\n\
		 '3am' 3,  ''  4, ''  5, \\\\\n\
		 '6am' 6,  ''  7, ''  8, \\\\\n\
		 '9am' 9,  '' 10, '' 11, \\\\\n\
		'12pm' 12, '' 13, '' 14, \\\\\n\
		 '3pm' 15, '' 16, '' 17, \\\\\n\
		 '6pm' 18, '' 19, '' 20, \\\\\n\
		 '9pm' 21, '' 22, '' 23  )" >> ${1:-$CONFIG_FILE}
	echo "set ytics 0,3" >> ${1:-$CONFIG_FILE}
	echo "set mytics 3" >> ${1:-$CONFIG_FILE}
	echo "set xlabel 'Time (Hours)'" >> ${1:-$CONFIG_FILE}
	echo "set ylabel 'Speed (Mbps)'" >> ${1:-$CONFIG_FILE}
	echo "set terminal gif" >> ${1:-$CONFIG_FILE}
	echo "set output '$DATA_FILE.${DATE_STRING:-yesterday}.gif'" >> ${1:-$CONFIG_FILE}
	echo "plot '$DATA_FILE' notitle, '$DATA_FILE' smooth csplines with lines" >> ${1:-$CONFIG_FILE}
}

# If possible, produce a graph of the data, using the given gnuplot script
function generate_graph {
	if [[ -z "$GNUPLOT_CMD" ]]; then
		echo "$0; ERROR: cannot find gnuplot, skipping graph generation"
		return 1
	fi
	echo -n "Generating graph for ${DATE_STRING:-yesterday}... "
	if $GNUPLOT_CMD ${1:-$CONFIG_FILE} &> /dev/null;
		then echo "SUCCESS"; return 0
		else echo "FAILURE"; return 1
	fi
}

# Labels the datafile with a given label, or the date
function rotate_data {
	if [[ -f "$DATA_FILE" ]]; then
		mv $DATA_FILE{,.${1:-${DATE_STRING:-yesterday}}.bak}
		return $?
	fi
	return 1
}

# Parse the command-line arguments
while getopts ":Vc:g:r:" OPT; do
	case $OPT in
	# -c: produce a gnuplot configuration
	c)
		write_conf $OPTARG
		exit $?
		;;
	# -g: force a graph generation
	g)
		generate_graph $OPTARG
		exit $?
		;;
	# -r: force a rotation of the datafile
	r)
		rotate_data $OPTARG
		exit $?
		;;
	# -V: print version information
	V)
		echo "$0; (tast -- Tor's Simple Automated Speed Test) v0.1"
		echo "USAGE: $0 [-cgvV] (-g requires gnuplot)"
		exit 0
		;;
	# Catch all unspecified parameters
	:)
		echo "$0; ERROR: option -$OPTARG requires argument"
		exit 1
		;;
	# Catch all unknown option flags
	\?)
		echo "$0; WARNING: ignoring unrecognized option -$OPTARG"
		;;
	esac
done

# Standard routine: adds a line to the datafile, and drives an update
echo "*** Starting speed test [$DATE_STRING] ***" | tee $LOG_FILE
if ping -c 1 -w 1 $WGET_DOMAIN &> /dev/null; then
	# Download step (small x5, medium x3, large x1)
	for i in ${WGET_FILE_ORDER[@]}; do
		WGET_FILE="http://$WGET_DOMAIN/${WGET_FILES[$i]}"
		echo -n "Fetching $WGET_FILE... "
		eval set -- $($WGET_CMD -O /dev/null --no-cache $WGET_FILE 2>&1 | tee -a $LOG_FILE | egrep -o '[0-9.]+ [KM]B')
		echo "Done [$1 $2]"
		if [[ -n $1 ]] && [[ -n $2 ]]; then
			case $2 in
				MB) VALUE=$(echo "$1 * 8" | bc -l);;
				KB) VALUE=$(echo "$1 / 128" | bc -l);;
			esac
			if [[ $i -eq 0 ]]; then SML_R[${#SML_R[*]}]=$VALUE; fi
			if [[ $i -eq 1 ]]; then MED_R[${#MED_R[*]}]=$VALUE; fi
			if [[ $i -eq 2 ]]; then LRG_R[${#LRG_R[*]}]=$VALUE; fi
		fi
	done
	# echo "Stabilization calculation (favor the mid cases)"
	SML_R_SUM=0; MED_R_SUM=0; LRG_R_SUM=0; SML_R_VAR=0; MED_R_VAR=0; LRG_R_VAR=0;
	NUM_R=$(( ${#SML_R[@]} + ${#MED_R[@]} + ${#LRG_R[@]} ))
	# echo "Calculate the weighted average"
	for R in ${SML_R[@]}; do SML_R_SUM=$(echo "$SML_R_SUM + $R" | bc -l); done
	for R in ${MED_R[@]}; do MED_R_SUM=$(echo "$MED_R_SUM + $R" | bc -l); done
	for R in ${LRG_R[@]}; do LRG_R_SUM=$(echo "$LRG_R_SUM + $R" | bc -l); done
	AVG_R=$(echo "($SML_R_SUM + $MED_R_SUM + $LRG_R_SUM) / $NUM_R" | bc -l)
	# echo "Calculate the standard deviation"
	for R in ${SML_R[@]}; do SML_R_VAR=$(echo "$SML_R_VAR + ($R - $AVG_R)^2" | bc -l); done
	for R in ${MED_R[@]}; do MED_R_VAR=$(echo "$MED_R_VAR + ($R - $AVG_R)^2" | bc -l); done
	for R in ${LRG_R[@]}; do LRG_R_VAR=$(echo "$SML_R_VAR + ($R - $AVG_R)^2" | bc -l); done
	STD_R=$(echo "sqrt(($SML_R_VAR + $MED_R_VAR + $LRG_R_VAR) / ($NUM_R - 1))" | bc -l)
	# echo "Filter the results for normalcy"
	for R in ${SML_R[@]}; do
		if [[ $(echo "($AVG_R - $R) < $STD_R" | bc -l) -eq 1 ]]
			then FINAL_R[${#FINAL_R[*]}]=$R
		fi
	done
	for R in ${MED_R[@]}; do
		if [[ $(echo "($AVG_R - $R) < $STD_R" | bc -l) -eq 1 ]]
			then FINAL_R[${#FINAL_R[*]}]=$R
		fi
	done
	for R in ${LRG_R[@]}; do
		if [[ $(echo "($AVG_R - $R) < $STD_R" | bc -l) -eq 1 ]]
			then FINAL_R[${#FINAL_R[*]}]=$R
		fi
	done
fi
# Compute the average of the normalized results, then print counts
RESULT=0
for R in ${FINAL_R[@]}; do
	RESULT=$(echo "$RESULT + $R / ${#FINAL_R[*]}" | bc -l)
done
RESULT=$(echo "scale=4; $RESULT / 1" | bc -l | tee -a $DATA_FILE)
ENTRIES="$(wc -l $DATA_FILE | cut -d ' ' -f 1)"
echo "*** Finished speed test ($ENTRIES) [$RESULT Mbps] ***" | tee -a $LOG_FILE
#echo -e "${SML_R[@]}\n${MED_R[@]}\n${LRG_R[@]}\nn: $NUM_R, avg: $AVG_R, std: $STD_R\n${FINAL_R[@]}"
# On the 24th, 48th, etc... invocation, do a generation and rotation
if [[ $(( $ENTRIES % 24 )) -eq 0 ]];
	then write_conf && generate_graph && rotate_data
fi

