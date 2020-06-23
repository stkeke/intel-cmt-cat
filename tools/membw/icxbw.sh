#!/bin/bash

CMD_HOME="$HOME/intel-cmt-cat"
PQOS="$CMD_HOME/pqos/pqos"
MEMBW="$CMD_HOME/tools/membw/membw"
RDTSET="$CMD_HOME/rdtset/rdtset"

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



# run qpos command to get monitor data 
# $1: output data file to write
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
		sudo $PQOS -m "$m_opt" -t "$t_opt" -o $data_file -u csv
		sudo sed -i -e "1,$(($cores+1))d" $data_file
		
		# sort by cores
		sudo sort -k 2,2 -k 1,1 -t "," $data_file > $data_file.sorted
		sudo cp -f $data_file.sorted $data_file
		sudo rm -f $data_file.sorted
}

################ process data file Begin ###############
# $1: data file name
function pqos_get_all_cores()
{
	awk -F"," '{print $2}' $1 | sort -n | uniq | sed -e 's/"//g' | sort -n
} 

function pqos_get_ipc_by_core()
{
	local data_file="$1"
	local core="$2"

	grep \"$core\" $data_file | awk -F"," '{print $3}'
}

function pqos_get_llc_by_core()
{
	local data_file="$1"
	local core="$2"

	grep \"$core\" $data_file | awk -F"," '{print $5}'
}

function pqos_get_mbl_by_core()
{
	local data_file="$1"
	local core="$2"

	grep \"$core\" $data_file | awk -F"," '{print $6}'
}

function pqos_get_mbr_by_core()
{
	local data_file="$1"
	local core="$2"

	grep \"$core\" $data_file | awk -F"," '{print $7}'
}

function pqos_get_avg_ipc_by_core()
{
	local data_file="$1"
	local core="$2"

	local lines=$(pqos_get_ipc_by_core $data_file $core | wc -l)
	local total=$(pqos_get_ipc_by_core $data_file $core | paste -sd+ | bc)
	echo "scale=2; $total/$lines" | bc | awk '{printf "%.2f\n", $0}'
}

function pqos_get_avg_llc_by_core()
{
	local data_file="$1"
	local core="$2"

	local lines=$(pqos_get_llc_by_core $data_file $core | wc -l)
	local total=$(pqos_get_llc_by_core $data_file $core | paste -sd+ | bc)
	echo "scale=2; $total/$lines" | bc | awk '{printf "%.1f\n", $0}'
}

function pqos_get_avg_mbl_by_core()
{
	local data_file="$1"
	local core="$2"

	local lines=$(pqos_get_mbl_by_core $data_file $core | wc -l)
	local total=$(pqos_get_mbl_by_core $data_file $core | paste -sd+ | bc)
	echo "$total/$lines" | bc 
}

function pqos_get_avg_mbr_by_core()
{
	local data_file="$1"
	local core="$2"

	local lines=$(pqos_get_mbr_by_core $data_file $core | wc -l)
	local total=$(pqos_get_mbr_by_core $data_file $core | paste -sd+ | bc)
	echo "$total/$lines" | bc 
}


function pqos_get_total_mbl()
{
	local data_file="$1"

	# calculate total bw
	local cores="0"
	local total="0"

	for i in $(pqos_get_all_cores $data_file)
	do
		local avg=$(pqos_get_avg_mbl_by_core $data_file $i)
		total=$(($total + $avg))
	done

	echo "TOTAL: $total"
}

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


################ membw mba benchmark ###########
# $1: start core#
# $2: end core# 
# $3: mba
function membw_run_write_on_cores_with_mba()
{
	# reset all COS
	sudo $PQOS -R 

	if (( $1 == $2 )); then
			sudo $PQOS -e "mba:1=$3"
			sudo $PQOS -a "llc:1=$1"
			membw_run_write_on_core $1
	else
			local cpus_list="$1-$(( $2/2 ))" 
	 		sudo $PQOS -e "mba:1=$3"
			sudo $PQOS -a "llc:1=$cpus_list"
			membw_run_write_on_cores $1 $2
	fi
	sleep 3
}


function membw_run_read_on_core()
{
	$MEMBW -c $1 -b 100000 --read &
}

# $1: the first core
# $2: the last core
function membw_run_write_on_cores()
{
	local i="0"
	for (( i=$1; i<=$2; i++))
	do
		membw_run_write_on_core $i &
	done
}

function membw_run_write_on_core()
{
	$MEMBW -c $1 -b 100000 --write &
}

function membw_run_read_on_core()
{
	$MEMBW -c $1 -b 100000 --read &
}

function membw_kill()
{
	pkill -9 membw
	sleep 3
}

function mba_cos1_set_mb()
{
	sudo umount /sys/fs/resctrl/
	sleep 1
	sudo $PQOS -I -e "mba:1=$1"
	sleep 1
}

function mba_cos1_reset()
{
	sudo $PQOS -I -e "mba:1=100"
	sleep 1
}

function mba_cos1_bind_cores()
{
	sudo su -c "echo $1 > /sys/fs/resctrl/COS1/cpus_list"
	# cat /sys/fs/resctrl/COS1/cpus_list
	sleep 1
}

# first run benchmark_write_mba() 
# then run benchmark_parse_data_file /tmp/result.mba.log to generate report
function benchmark_write_mba()
{
	local result_file="/tmp/result.mba.log"
	rm -rf $result_file && touch $result_file

	membw_kill

	for i in {1..12}
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

function benchmark_parse_data_file()
{
	local data_file="$1"

	# cores is also processes
	# local cores="$2"

	# get total bw for each MBA=10,20,30,40
	echo "MBA TOTAL Processes=1..12"
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
	for p in {1..12}
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

function benchmark_membw()
{
	membw_kill

	for i in {1..12}
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


function run_membw_test()
{
	kill_membw && sleep 1 && run_membw_write_on_cores 1 12 > /tmp/bw.log
	grep AVG /tmp/bw.log | sort -k 2 -n
	grep TOTAL /tmp/bw.log
}
