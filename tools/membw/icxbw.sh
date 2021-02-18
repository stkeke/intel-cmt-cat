#!/bin/bash

# This script is used to benchmark RDT on ICX (IceLake) platform

CMD_HOME="$HOME/intel-cmt-cat"
PQOS="$CMD_HOME/pqos/pqos"
MEMBW="$CMD_HOME/tools/membw/membw"
RDTSET="$CMD_HOME/rdtset/rdtset"

# Total cores you want to benchmark
# We start benchmark from the 2nd core (ie. core#=1), until to $CORES.
# Usually, set to cores per socket
CORES=39

if [[ ! -x "$PQOS" ]]; then
	echo "PQOS command ($PQOS) not found"
	return
fi

if [[ ! -x "$MEMBW" ]]; then
	echo "MEMBW command ($MEMBW) not found"
	return
fi

if [[ ! -x "$RDTSET" ]]; then
	echo "RDTSET command ($RDTSET) not found"
	return
fi

# collect system information
function rdt_get_information()
{
	sudo $PQOS -I -D
}

echo "Usage: "
echo "rdt_get_information: print out RDT information"
echo "rdt_mba_benchmark: run MBA benchmark"

# ======== PRIVATE FUNCTION ========
# Function: run qpos command to collect monitor data and sort by core#
# $1: output sorted data file
# $2: last core to monitor, from 1-$2
function pqos_collect_data_by_cores()
{
		local data_file="$1"
		local cores="$2"

		local m_opt=""
		local t_opt="10"

		if (( $cores == 1 )); then
			m_opt="all:1"
		else
			m_opt="all:1-$cores"
		fi

		# remove unused lines
		sudo $PQOS -I -m "$m_opt" -t "$t_opt" -o $data_file -u csv
		sudo sed -i -e "1,$(($cores+1))d" $data_file

		# sort by cores
		sudo sort -k 2,2 -k 1,1 -t "," $data_file > $data_file.sorted
		sudo cp -f $data_file.sorted $data_file
		sudo rm -f $data_file.sorted
}

################ process data file Begin ###############
# Function: get all monitored cores from log file and print out to screen
# $1: data file name
function pqos_get_all_cores()
{
	awk -F"," '{print $2}' $1 | sort -n | uniq | sed -e 's/"//g' | sort -n
}

# Function: get IPC by core# from data file
# $1: data file name
# $2: core#
function pqos_get_ipc_by_core()
{
	local data_file="$1"
	local core="$2"

	grep \"$core\" $data_file | awk -F"," '{print $3}'
}

# Function: get LLC by core# from data file
# $1: data file name
# $2: core#
function pqos_get_llc_by_core()
{
	local data_file="$1"
	local core="$2"

	grep \"$core\" $data_file | awk -F"," '{print $5}'
}

# Function: get MBL (MB Local) by core# from data file
# $1: data file name
# $2: core#
function pqos_get_mbl_by_core()
{
	local data_file="$1"
	local core="$2"

	grep \"$core\" $data_file | awk -F"," '{print $6}'
}

# Function: get MBR (MB Remote) by core# from data file
# $1: data file name
# $2: core#
function pqos_get_mbr_by_core()
{
	local data_file="$1"
	local core="$2"

	grep \"$core\" $data_file | awk -F"," '{print $7}'
}

# =========== Calcuate AVG value for each perf. metric ===========
# Function: calcuate average IPC by core# from data file
# $1: data file name
# $2: core#
function pqos_get_avg_ipc_by_core()
{
	local data_file="$1"
	local core="$2"

	local lines=$(pqos_get_ipc_by_core $data_file $core | wc -l)
	local total=$(pqos_get_ipc_by_core $data_file $core | paste -sd+ | bc)
	echo "scale=2; $total/$lines" | bc | awk '{printf "%.2f\n", $0}'
}

# Function: calcuate average LLC by core# from data file
# $1: data file name
# $2: core#
function pqos_get_avg_llc_by_core()
{
	local data_file="$1"
	local core="$2"

	local lines=$(pqos_get_llc_by_core $data_file $core | wc -l)
	local total=$(pqos_get_llc_by_core $data_file $core | paste -sd+ | bc)
	echo "scale=2; $total/$lines" | bc | awk '{printf "%.1f\n", $0}'
}

# Function: calcuate average MB Local by core# from data file
# $1: data file name
# $2: core#
function pqos_get_avg_mbl_by_core()
{
	local data_file="$1"
	local core="$2"

	local lines=$(pqos_get_mbl_by_core $data_file $core | wc -l)
	local total=$(pqos_get_mbl_by_core $data_file $core | paste -sd+ | bc)
	echo "$total/$lines" | bc
}

# Function: calcuate average MB Remote by core# from data file
# $1: data file name
# $2: core#
function pqos_get_avg_mbr_by_core()
{
	local data_file="$1"
	local core="$2"

	local lines=$(pqos_get_mbr_by_core $data_file $core | wc -l)
	local total=$(pqos_get_mbr_by_core $data_file $core | paste -sd+ | bc)
	echo "$total/$lines" | bc
}


# =========== Calcuate TOTAL value for each perf. metric ===========
# Function: calcuate total MB Local from data file and print out to screen
# $1: data file name
function pqos_get_total_mbl()
{
	local data_file="$1"

	# calculate total bw
	local total="0"

	for i in $(pqos_get_all_cores $data_file)
	do
		local avg=$(pqos_get_avg_mbl_by_core $data_file $i)
		total=$(($total + $avg))
	done

	echo "TOTAL: $total"
}

# Function: calcuate avg MB Local for each core from data file
# and print out to screen
# $1: data file name
function pqos_get_avg_mbl_for_each_core()
{
	local data_file="$1"
	for i in $(pqos_get_all_cores $data_file)
	do
		local avg=$(pqos_get_avg_mbl_by_core $data_file $i)
		echo "AVG: $i: $avg"
	done
}
################ process data file END ###############


################ membw helper functions ###########
################ MBA write benchmark by membw ###########
# Function: start membw write operation on specified core
# 	and put the task in background
# $1: core#
function membw_run_write_on_core()
{
	$MEMBW -c $1 -b 100000 --write &
}

# Function: start membw write operation on specified cores
# $1: the first core
# $2: the last core
function membw_run_write_on_cores()
{
	local i="0"
	for (( i=$1; i<=$2; i++ ))
	do
		membw_run_write_on_core $i
	done
}

# $1: start core#
# $2: end core#
# $3: mba
function membw_run_write_on_cores_with_mba()
{
	# reset all COS
	sudo $PQOS -I -R

	if (( $1 == $2 )); then
			# -e CLASSDEF; -a CLASS2ID
			sudo $PQOS -I -e "mba:1=$3"
			sudo $PQOS -I -a "llc:1=$1"
			membw_run_write_on_core $1
	else
			# local cpus_list="$1-$(( $2/2 ))"
			local cpus_list="$1-$2"
	 		sudo $PQOS -I -e "mba:1=$3"
			sudo $PQOS -I -a "llc:1=$cpus_list"
			membw_run_write_on_cores $1 $2
	fi
	# sleep 3 seconds for membw to warmup
	sleep 3
}

################ MBA read benchmark by membw ###########
# Function: start membw read operation on specified core
# 	and put the task in background
# $1: core#
function membw_run_read_on_core()
{
	$MEMBW -c $1 -b 100000 --read &
}

# Function: kill all membw processes started for benchmarking
function membw_kill()
{
	pkill -9 membw
	sleep 3
}


# ================= For Future Use Begin =================
# Function: use COS1 to set MB limit value
# $1: MB limit value
function mba_cos1_set_mb()
{
	sudo umount /sys/fs/resctrl/
	sleep 1
	sudo $PQOS -I -e "mba:1=$1"
	sleep 1
}

# Function: reset COS1 to 100
function mba_cos1_reset()
{
	sudo $PQOS -I -e "mba:1=100"
	sleep 1
}

# Function: bind COS1 to cores
# $1: core#
function mba_cos1_bind_cores()
{
	sudo su -c "echo $1 > /sys/fs/resctrl/COS1/cpus_list"
	# cat /sys/fs/resctrl/COS1/cpus_list
	sleep 1
}
# ================= For Future Use End =================

# ========== Usage for end user ============
# first run benchmark_write_mba()
# then run benchmark_parse_data_file /tmp/result.mba.log to generate report
# $1: CORES (to replace global variable CORES)
function rdt_mba_benchmark()
{
	if [[ -n "$1" ]]; then
		CORES=$1
	fi
	benchmark_write_mba
	benchmark_parse_data_file /tmp/result.mba.log
}

function benchmark_write_mba()
{
	local result_file="/tmp/result.mba.log"
	rm -rf $result_file && touch $result_file

	membw_kill

	for ((i=1; i<=$CORES; i++))
	do
		echo "Beanchmark $i membw processes" | tee -a $result_file

		for j in {10..100..10}
		do
			local data_file="/tmp/cores-$i-$j.log"
			echo "COS1 MBA=$j" | tee -a $result_file
			membw_run_write_on_cores_with_mba 1 $i $j

			pqos_collect_data_by_cores $data_file $i
			pqos_get_total_mbl $data_file | tee -a $result_file
			pqos_get_avg_mbl_for_each_core $data_file | tee -a $result_file
			membw_kill
		done
	done
	membw_kill
}

# Function: parse data file to generate a report
# $1: data file
function benchmark_parse_data_file()
{
	local data_file="$1"

	# cores is also processes
	# local cores="$2"

	echo "MBA TOTAL Processes=1..${CORES}"
	# get total bw for each MBA=10,20,30,40
	for m in {10..100..10}
	do
		local filter="MBA=$m"
		echo "$m $(grep -w "$filter" -A 1 $data_file | grep TOTAL | sed -e 's/TOTAL: //' | paste -sd' ')"
	done

	echo "MBA Avg Core1  Mem BW (MB/s)"
	for m in {10..100..10}
	do
		local filter="MBA=$m"
		echo "$m $(grep -w "$filter" -A 2 $data_file | grep "AVG: 1:" | sed -e "s/AVG: 1: //" | paste -sd' ')"
	done

	echo "MBA Per Core Mem BW (MB/s)"
	for ((p=1; p<=$CORES; p++))
	do
		echo "Process=$p"
		for m in {10..100..10}
		do
			local filter="MBA=$m"
			echo "$m $(sed -n -e "/Beanchmark $p membw processes/,/Beanchmark $((p+1)) membw processes/p" $data_file |
				grep -w "$filter" -A $((p + 2)) | grep "AVG: " | sed -e "s/AVG:.*: //" | paste -sd' ')"
		done
	done

}

# Function: benchmark each core
function benchmark_membw()
{
	membw_kill

	# TODO: change to ICX cores
	for ((i=1; i<=$CORES; i++))
	do
		local data_file="/tmp/cores-$i.log"

		echo "Beanchmark $i membw processes"

		membw_run_write_on_cores 1 $i

		pqos_collect_data_by_cores $data_file $i
		pqos_get_total_mbl $data_file
		pqos_get_avg_mbl_for_each_core $data_file
	done

	membw_kill
}
