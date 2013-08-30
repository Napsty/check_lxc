#!/bin/bash 
################################################################################
# Script:       check_lxc.sh                                                   #
# Author:       Claudio Kuenzler (www.claudiokuenzler.com)                     #
# Purpose:      Monitor LXC                                                    #
# Full Doc:	www.claudiokuenzler.com/nagios-plugins/check_lxc.php           #
#                                                                              #
# Licence:      GNU General Public Licence (GPL) http://www.gnu.org/           #
# This program is free software; you can redistribute it and/or                #
# modify it under the terms of the GNU General Public License                  #
# as published by the Free Software Foundation; either version 2               #
# of the License, or (at your option) any later version.                       #
#                                                                              #
# This program is distributed in the hope that it will be useful,              #
# but WITHOUT ANY WARRANTY; without even the implied warranty of               #
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the                 #
# GNU General Public License for more details.                                 #
#                                                                              #
# You should have received a copy of the GNU General Public License            #
# along with this program; if not, write to the Free Software                  #
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA                #
# 02110-1301, USA.                                                             #
#                                                                              #
# History:                                                                     #
# 20130830 Finished first check (mem)                                          #
################################################################################
# Usage: ./check_lxc.sh -n container -t type [-w warning] [-c critical] 
################################################################################
# Definition of variables
version="0.1"
STATE_OK=0              # define the exit code if status is OK
STATE_WARNING=1         # define the exit code if status is Warning
STATE_CRITICAL=2        # define the exit code if status is Critical
STATE_UNKNOWN=3         # define the exit code if status is Unknown
PATH=/usr/local/bin:/usr/bin:/bin # Set path
################################################################################
# The following commands are required
for cmd in lxc-ls lxc-cgroup egrep awk; 
do if ! `which ${cmd} 1>/dev/null`
  then echo "UNKNOWN: ${cmd} does not exist, please check if command exists and PATH is correct"
  exit ${STATE_UNKNOWN}
fi
done
################################################################################
# Mankind needs help
help="$0 v ${version} (c) 2013 Claudio Kuenzler
Usage: $0 -n container -t type [-u unit] [-w warning] [-c critical]
Options:\n\t-n name of container\n\t-t type to check (see list below)\n\t[-u unit of output values (k|m|g)]\n\t[-w warning threshold (percent)]\n\t[-c critical threshold (percent)]
Types:\n\tmem -> Check the memory usage of the given container\n\tswap -> Check the swap usage"
################################################################################
# Check for people who need help - aren't we all nice ;-)
if [ "${1}" = "--help" -o "${#}" = "0" ];
       then
       echo -e "${help}";
       exit 1;
fi
################################################################################
# Get user-given variables
while getopts "n:t:u:w:c:" Input;
do
       case ${Input} in
       n)      container=${OPTARG};;
       t)      type=${OPTARG};;
       u)      unit=${OPTARG};;
       w)      warning=${OPTARG};;
       c)      critical=${OPTARG};;
       *)      echo -e "${help}"; exit $STATE_UNKNOWN;;
       esac
done
################################################################################
# Check that all required options were given
if [[ -z ${container} ]] || [[ -z ${type} ]]; then 
echo -e "${help}"; exit $STATE_UNKNOWN
fi
################################################################################
# Functions
#lxc_exists() {
#lxc-ls | grep -x ${container} 1>/dev/null || echo "LXC ${container} not found on system"; exit $STATE_CRITICAL
#}

threshold_sense() {
	if [[ -n $warning ]] && [[ -z $critical ]]; then echo "Both warning and critical thresholds must be set"; exit $STATE_UNKNOWN; fi
	if [[ -z $warning ]] && [[ -n $critical ]]; then echo "Both warning and critical thresholds must be set"; exit $STATE_UNKNOWN; fi
	if [[ $warning -gt $critical ]]; then echo "Warning threshold cannot be greater than critical"; exit $STATE_UNKNOWN; fi
}

################################################################################
# Checks
case ${type} in
mem)	# Memory Check - Reference: https://www.kernel.org/doc/Documentation/cgroups/memory.txt
	#used=$(lxc-cgroup -n ${container} memory.usage_in_bytes)
	rss=$(lxc-cgroup -n ${container} memory.stat | egrep '^rss [[:digit:]]' | awk '{print $2}')
	cache=$(lxc-cgroup -n ${container} memory.stat | egrep '^cache [[:digit:]]' | awk '{print $2}')
	swap=$(lxc-cgroup -n ${container} memory.stat | egrep '^swap [[:digit:]]' | awk '{print $2}')
	used=$(( $rss + $cache + $swap))

	# Calculate wanted output - defaults to m
	if [[ -n ${unit} ]]; then 
	  case ${unit} in
	  k)	used_output="$(( $used / 1024)) KB" ;;
	  m)	used_output="$(( $used / 1024 / 1024)) MB" ;;
	  g)	used_output="$(( $used / 1024 / 1024 / 1024)) GB" ;;
	  *)	echo -e "${help}"; exit $STATE_UNKNOWN;;
	  esac
	else used_output="$(( $used / 1024 / 1024)) MB" 
	fi

	# Threshold checks
	if [[ -n $warning ]] && [[ -n $critical ]]
	then
	  threshold_sense
	  limit=$(lxc-cgroup -n ${container} memory.limit_in_bytes)
	  used_perc=$(( $used * 100 / $limit))
	  if [[ $used_perc -ge $critical ]]
		then echo "LXC ${container} CRITICAL - Used Memory: ${used_perc}% (${used_output})|mem_used=${used}B;0;0;0;${limit}"
		exit $STATE_CRITICAL
	  elif [[ $used_perc -ge $warning ]]
		then echo "LXC ${container} WARNING - Used Memory: ${used_perc}% (${used_output})|mem_used=${used}B;0;0;0;${limit}"
		exit $STATE_WARNING
	  else 	echo "LXC ${container} OK - Used Memory: ${used_perc}% (${used_output})|mem_used=${used}B;0;0;0;${limit}"
		exit $STATE_OK
	  fi
	else echo "LXC ${container} OK - Used Memory: ${used_output}|mem_used=${used}B;0;0;0;${limit}"; exit $STATE_OK
	fi
	;;
esac
