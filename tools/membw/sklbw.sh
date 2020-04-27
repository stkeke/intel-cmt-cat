#!/bin/bash

CMD_HOME=/opt/stack/intel-cmt-cat
PQOS=$CMD_HOME/pqos/pqos
MEMBW=$CMD_HOME/tools/membw/membw

if [[ ! -x "$PQOS" ]]; then
	echo "PQOS command ($PQOS) not found"
	exit 1
fi

if [[ ! -x "$MEMBW" ]]; then
	echo "MEMBW command ($MEMBW) not found"
	exit 1
fi

# $1: core# 
function run_membw_write_on_core()
{
	$MEMBW -c $1 -b 100000 --write &
	# echo "$!"
}

# $1: the first core
# $2: the last core
function run_membw_write_on_cores()
{
	local pids=""
	for (( i=$1; i<=$2; i++))
	do
		run_membw_write_on_core $i

		# collect performance data
		local data_file=""
		local m_opt=""
		local t_opt="6"
		if (( $i == 1)); then
			data_file=/tmp/core1.log
			m_opt="all:1"
		else
			data_file=/tmp/core1-$i.log
			m_opt="all:1-$i"
		fi

		# remove unused lines
		sudo $PQOS -m "$m_opt" -t "$t_opt" -o $data_file -T -u csv >/dev/null 2>&1
		sudo sed -i -e "1,$(($i+1))d" $data_file

		# sort by cores
		sudo sort -k 2 -t "," $data_file > $data_file.sorted

		# calculate total bw
		total="$(awk -F"," '{print $6}' $data_file.sorted | paste -sd+ | bc)"
		total_bw="$( echo $total / $t_opt | bc)"
		echo "TOTAL: $i: $total_bw"
		
		# calculate average bw
		for(( j=1; j<=i; j++ ))
		do
			# grep by core
			total="$(grep \"$j\" $data_file.sorted | awk -F"," '{print $6}' | paste -sd+ | bc)"
			avg_bw="$( echo $total / $t_opt | bc)"
			echo "AVG: $j: $avg_bw"
		done
	done
}


function kill_membw()
{
	pkill -9 membw
}

kill_membw && sleep 1 && run_membw_write_on_cores 1 17 > /tmp/bw.log
grep AVG /tmp/bw.log | sort -k 2 -n
grep TOTAL /tmp/bw.log