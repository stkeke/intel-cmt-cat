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

# $1: core# 
function membw_run_write_on_core()
{
	$MEMBW -c $1 -b 100000 --write &
	# for data warmup 
	sleep 1
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
	# for data warmup
	sleep 3
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

function benchmark_mba()
{
	membw_kill

	for i in {1..3}
	do
		echo "Beanchmark $i membw processes"

		membw_run_write_on_cores 1 $i

		for j in {10..20..10}
		do
			local data_file="/tmp/cores-$i-$j.log"
			echo "COS1 MBA=$j"		
			mba_cos1_set_mb $j
			# mba_cos1_bind_cores 1			

			pqos_collect_data_by_cores $data_file $i
			pqos_get_total_mbl $data_file
			pqos_get_avg_mbl_for_each_core $data_file
		done
		echo "kill membw processes"
		membw_kill
	done
}

function benchmark_membw()
{
	membw_kill

	for i in {1..17}
	do
		local data_file="/tmp/cores-$i.log"
		
		echo "Beanchmark $i membw processes"

		membw_run_write_on_cores 1 $i

		pqos_collect_data_by_cores $data_file $i
		pqos_get_total_mbl $data_file
		pqos_get_avg_mbl_for_each_core $data_file
	done
}

function run_membw_test()
{
	kill_membw && sleep 1 && run_membw_write_on_cores 1 17 > /tmp/bw.log
	grep AVG /tmp/bw.log | sort -k 2 -n
	grep TOTAL /tmp/bw.log
}
