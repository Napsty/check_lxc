#!/bin/bash 
################################################################################
# Script:       check_lxc.sh                                                   #
# Author:       Claudio Kuenzler (www.claudiokuenzler.com)                     #
# Purpose:      Monitor LXC                                                    #
# Full Doc:     www.claudiokuenzler.com/monitoring-plugins/check_lxc.php       #
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
# 20130902 Added cgroup kernel boot parameter check (cgroup_active)            #
# 20130902 Fixed previous cgroup check (see issue #1)                          #
# 20130902 Activated lxc_exists verification (finally turned to lxc_running)   #
# 20130902 Added new check type (auto)                                         #
# 20130912 Reorganizing code, put output calculation into function             #
# 20130912 Added new check type (swap)                                         #
# 20130913 Bugfix in swap check warning calculation                            #
# 20160316 Make plugin work with LXC 1.x, too                                  #
# 20160316 In LXC 1.x, lxc-cgroup command needs sudo                           #
# 20160318 Additional checks if swap value can be read                         #
# 20160318 Perfdata of mem check: Only show 'max' when thresholds set          #
# 20160318 Adapt lxc_running function to work on 1.x, too                      #
# 20160318 Add warn and crit values into mem check perfdata                    #
# 20160318 Remove sudo commands within plugin, whole plugin requires sudo      #
# 20170710 Added cpu check type                                                #
################################################################################
# Usage: ./check_lxc.sh -n container -t type [-w warning] [-c critical] 
################################################################################
# Definition of variables
version="0.6.0"
STATE_OK=0              # define the exit code if status is OK
STATE_WARNING=1         # define the exit code if status is Warning
STATE_CRITICAL=2        # define the exit code if status is Critical
STATE_UNKNOWN=3         # define the exit code if status is Unknown
sleep=5                 # define the sleep time between cpu checks
PATH=/usr/local/bin:/usr/bin:/bin # Set path
################################################################################
# The following base commands are required
for cmd in grep egrep awk sed lxc-info lxc-ls lxc-cgroup; 
do if ! `which ${cmd} 1>/dev/null`
  then echo "UNKNOWN: ${cmd} does not exist, please check if command exists and PATH is correct"
  exit ${STATE_UNKNOWN}
fi
done
################################################################################
# LXC 0.x and 1.x commands are different. The following lxc commands are required.
lxcversion=$((lxc-version 2>/dev/null || lxc-start --version) | sed 's/.* //' | awk -F. '{print $1}')

if [[ $lxcversion -eq 0 ]]; then
  for cmd in lxc-list; 
  do if ! `which ${cmd} 1>/dev/null`
    then echo "UNKNOWN: ${cmd} does not exist, please check if command exists and PATH is correct"
    exit ${STATE_UNKNOWN}
  fi
  done
fi
################################################################################
# Mankind needs help
help="$0 v ${version} (c) 2013-$(date +%Y) Claudio Kuenzler
Usage: $0 -n container -t type [-u unit] [-w warning] [-c critical]
Options:\n\t-n name of container\n\t-t type to check (see list below)\n\t[-u unit of output values (k|m|g)]\n\t[-w warning threshold] (for memory makes only sense if limit is set in lxc config)\n\t[-c critical threshold] (for memory makes only sense if limit is set in lxc config)\n\t[-s sleep in seconds between cpu checks]
Types:\n\tmem -> Check the memory usage of the given container (thresholds in percent)\n\tswap -> Check the swap usage (thresholds in MB)\n\tcpu -> Check cpu usage (percentage) of a container (thresholds in percent)\n\tauto -> Check autostart of container (-n ALL possible)"
################################################################################
# Check for people who need help - aren't we all nice ;-)
if [ "${1}" = "--help" -o "${#}" = "0" ];
       then
       echo -e "${help}";
       exit 1;
fi
################################################################################
# Get user-given variables
while getopts "n:t:u:w:c:s:" Input;
do
       case ${Input} in
       n)      container=${OPTARG};;
       t)      type=${OPTARG};;
       u)      unit=${OPTARG};;
       w)      warning=${OPTARG};;
       c)      critical=${OPTARG};;
       s)      sleep=${OPTARG};;
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
lxc_running() {
if [[ ${container} != "ALL" ]]; then
  lxc-info -n ${container} >/dev/null 2>&1
  if [[ $? -gt 0 ]]
  then echo "LXC ${container} not found on system"; exit $STATE_CRITICAL
  else 
    if [[ $(lxc-info -n ${container} | grep -i state | awk '{print $2}') = "STOPPED" ]]
    then echo "LXC ${container} not found or not running on system"; exit $STATE_CRITICAL
    fi
  fi
fi
}
threshold_sense() {
if [[ -n $warning ]] && [[ -z $critical ]]; then echo "Both warning and critical thresholds must be set"; exit $STATE_UNKNOWN; fi
if [[ -z $warning ]] && [[ -n $critical ]]; then echo "Both warning and critical thresholds must be set"; exit $STATE_UNKNOWN; fi
if [[ $warning -gt $critical ]]; then echo "Warning threshold cannot be greater than critical"; exit $STATE_UNKNOWN; fi
}
cgroup_memory_active() {
if [[ $(cat /proc/cgroups | grep memory | awk '{print $4}') -eq 0 ]]; then echo "cgroup is not defined as kernel cmdline parameter (cgroup_enable=memory)"; exit $STATE_UNKNOWN; fi
}
unit_calculate() {
# Calculate wanted output - defaults to m
if [[ -n ${unit} ]]; then 
  case ${unit} in
  k)    used_output="$(( $used / 1024)) KB" ;;
  m)    used_output="$(( $used / 1024 / 1024)) MB" ;;
  g)    used_output="$(( $used / 1024 / 1024 / 1024)) GB" ;;
  *)    echo -e "${help}"; exit $STATE_UNKNOWN;;
  esac
else used_output="$(( $used / 1024 / 1024)) MB" 
fi
}
################################################################################
# Simple check if container is running
lxc_running
################################################################################
# Check Types
case ${type} in
mem)    # Memory Check - Reference: https://www.kernel.org/doc/Documentation/cgroups/memory.txt
        # cgroup memory support must be enabled
        cgroup_memory_active

        # Get the values
        #used=$(lxc-cgroup -n ${container} memory.usage_in_bytes)
        rss=$(lxc-cgroup -n ${container} memory.stat | egrep '^rss [[:digit:]]' | awk '{print $2}')
        cache=$(lxc-cgroup -n ${container} memory.stat | egrep '^cache [[:digit:]]' | awk '{print $2}')
        swap=$(lxc-cgroup -n ${container} memory.stat | egrep '^swap [[:digit:]]' | awk '{print $2}')
        # When kernel is booted without swapaccount=1, swap value doesnt show up. Assuming 0 in this case.
        if [[ -z $swap ]] || [[ $swap = "" ]]; then swap=0; fi
        used=$(( $rss + $cache + $swap))
	limit=$(lxc-cgroup -n ${container} memory.limit_in_bytes)
        used_perc=$(( $used * 100 / $limit))

        # Calculate wanted output - defaults to m
	unit_calculate

        # Threshold checks
        if [[ -n $warning ]] && [[ -n $critical ]]
        then
          threshold_sense
          warnvalue=$(( $limit / 100 * $warning )); critvalue=$(( $limit / 100 * $critical ))
          if [[ $used_perc -ge $critical ]]
                then echo "LXC ${container} CRITICAL - Used Memory: ${used_perc}% (${used_output})|mem=${used}B;${warnvalue};${critvalue};0;${limit}"
                exit $STATE_CRITICAL
          elif [[ $used_perc -ge $warning ]]
                then echo "LXC ${container} WARNING - Used Memory: ${used_perc}% (${used_output})|mem=${used}B;${warnvalue};${critvalue};0;${limit}"
                exit $STATE_WARNING
          else  echo "LXC ${container} OK - Used Memory: ${used_perc}% (${used_output})|mem=${used}B;${warnvalue};${critcalue};0;${limit}"
                exit $STATE_OK
          fi
        else echo "LXC ${container} OK - Used Memory: ${used_output}|mem=${used}B;0;0;0;0"; exit $STATE_OK
        fi
        ;;
swap)   # Swap Check
        # cgroup memory support must be enabled
        cgroup_memory_active

        # Get the values
        used=$(lxc-cgroup -n ${container} memory.stat | egrep '^swap [[:digit:]]' | awk '{print $2}')

        # When kernel is booted without swapaccount=1, swap value doesnt show up. This check doesnt make sense then.
        if [[ -z $used ]] || [[ $used = "" ]]; then
          echo "Swap value for ${container} cannot be read. Make sure you activate swapaccount=1 in kernel cmdline"
          exit $STATE_UNKNOWN
        fi

        # Calculate wanted output - defaults to m
	unit_calculate

        # Threshold checks
        if [[ -n $warning ]] && [[ -n $critical ]]
        then
	  warningpf=$(( $warning * 1024 * 1024 ))
	  criticalpf=$(( $critical * 1024 * 1024 ))
          threshold_sense
          if [[ $used -ge $criticalpf ]]
                then echo "LXC ${container} CRITICAL - Used Swap: ${used_output}|swap=${used}B;${warningpf};${criticalpf};0;0"
                exit $STATE_CRITICAL
          elif [[ $used -ge $warningpf ]]
                then echo "LXC ${container} WARNING - Used Swap: ${used_output}|swap=${used}B;${warningpf};${criticalpf};0;0"
                exit $STATE_WARNING
          else  echo "LXC ${container} OK - Used Swap: ${used_output}|swap=${used}B;${warningpf};${criticalpf};0;0"
                exit $STATE_OK
          fi
        else echo "LXC ${container} OK - Used Swap: ${used_output}|swap=${used}B;${warningpf};${criticalpf};0;0"; exit $STATE_OK
        fi
	;;
auto)   # Autostart check
        if [[ ${container} = "ALL" ]]
        # All containers
        then 
          i=0
          for lxc in $(lxc-ls -1 | sort -u ); do
          if [[ $(lxc-info -n ${lxc} -s | awk '{print $2}') = "RUNNING" ]]; then 
            if [[ $lxcversion -eq 0 ]]; then 
              [[ -n $(lxc-list | grep ${lxc} | grep "(auto)") ]] || error[${i}]="${lxc} "
            fi
            else 
              [[ -n $(lxc-ls -f | grep ${lxc} | grep "YES") ]] || error[${i}]="${lxc} "
          fi
          done
          if [[ ${#error[*]} -gt 0 ]]
          then echo "LXC AUTOSTART CRITICAL: ${error[*]}"; exit $STATE_CRITICAL
          else echo "LXC AUTOSTART OK"; exit $STATE_OK
          fi
        else 
        # Single container
          if [[ $lxcversion -eq 0 ]]; then 
            if [[ -z $(lxc-list | grep ${container} | grep "(auto)") ]]
            then echo "LXC AUTOSTART CRITICAL: ${container}"; exit $STATE_CRITICAL
            else echo "LXC AUTOSTART OK"; exit $STATE_OK
            fi
          else
            if [[ -z $(lxc-ls -f | grep ${container} | grep "YES") ]]
            then echo "LXC AUTOSTART CRITICAL: ${container}"; exit $STATE_CRITICAL
            else echo "LXC AUTOSTART OK"; exit $STATE_OK
            fi
          fi
        fi
        ;;
cpu)    # CPU check
        # Get CPU jiffies statistics globally (using /proc/stat) and from container using cgroups
        # see https://www.kernel.org/doc/Documentation/filesystems/proc.txt (1.8 Miscellaneous kernel statistics in /proc/stat)
        # see https://www.kernel.org/doc/Documentation/cgroup-v1/cpuacct.txt
        proc1=$(cat /proc/stat | grep "^cpu ")
        cgroup1=$(lxc-cgroup -n ${container} cpuacct.stat)
        proccpu1=$(( $(echo $proc1 | awk -F' ' '{print $2}') + $(echo $proc1 | awk -F' ' '{print $4}') ))
        cgroupcpu1=$(( $(echo $cgroup1 | grep user | awk '{print $2}') + $(echo $cgroup1 | grep system | awk '{print $2}') ))
        sleep $sleep
        proc2=$(cat /proc/stat | grep "^cpu ")
        cgroup2=$(lxc-cgroup -n ${container} cpuacct.stat)
        proccpu2=$(( $(echo $proc2 | awk -F' ' '{print $2}') + $(echo $proc2 | awk -F' ' '{print $4}') ))
        cgroupcpu2=$(( $(echo $cgroup2 | grep user | awk '{print $2}') + $(echo $cgroup2 | grep system | awk '{print $2}') ))
        globaljiffies=$(( $proccpu2 - $proccpu1 ))
        lxcjiffies=$(( $cgroupcpu2 - $cgroupcpu1 ))
        lxcpercent=$(( $lxcjiffies * 100 / $globaljiffies))

         # Threshold checks
        if [[ -n $warning ]] && [[ -n $critical ]]
        then
          if [[ $lxcpercent -ge $critical ]]
                then echo "LXC ${container} CRITICAL - CPU Usage: ${lxcpercent}%|cpu=${lxcpercent}%;${warning};${critical};0;0"
                exit $STATE_CRITICAL
          elif [[ $lxcpercent -ge $warning ]]
                then echo "LXC ${container} WARNING - CPU Usage: ${lxcpercent}%|cpu=${lxcpercent}%;${warning};${critical};0;0"
                exit $STATE_WARNING
          else  echo "LXC ${container} OK - CPU Usage: ${lxcpercent}%|cpu=${lxcpercent}%;${warning};${critical};0;0"
                exit $STATE_OK
          fi
        else echo "LXC ${container} OK - CPU Usage: ${lxcpercent}%|cpu=${lxcpercent}%;${warning};${critical};0;0"; exit $STATE_OK
        fi
	;;
esac
