check_lxc
=========

Monitoring plugin to check LXC (Linux Container) 

Full documentation: https://www.claudiokuenzler.com/monitoring-plugins/check_lxc.php


Usage
-----
    sudo ./check_lxc.sh -n container -t type [-u unit] [-w warning] [-c critical]
    
sudo needed
-----------
check_lxc.sh requires to be run with root privileges because certain commands within the plugin require elevated permissions. Therefore create an entry in /etc/sudoers similar to this (adapt to your own environment):

    nagios          ALL = NOPASSWD: /usr/lib/nagios/plugins/check_lxc.sh
    
If you use NRPE, the corresponding command definition could look like this:

    command[check_lxc]=sudo /usr/lib/nagios/plugins/check_lxc.sh -n $ARG1$ -t $ARG2$
    
Options and check types explained
---------------------------------
    Options:
        -n name of container (or ALL for some types)
        -t type to check (see list below)
        [-u unit of output values (k|m|g)]
        [-w warning threshold] (makes only sense if limit is set in lxc config)
        [-c critical threshold] (makes only sense if limit is set in lxc config)
        [-s sleep in seconds between cpu checks]
        
    Types:
        mem -> Check the memory usage of the given container (thresholds in percent)
        swap -> Check the swap usage (thresholds in MB)
        cpu -> Check cpu usage (percentage) of a container (thresholds in percent)
        auto -> Check autostart of container (-n ALL possible)


Examples (container name: lxctest01)
------------------------------------
    ./check_lxc.sh -n lxctest01 -t mem 
    LXC lxctest01 OK - Used Memory: 96 MB|mem_used=100941824B;0;0;0;

    ./check_lxc.sh -n lxctest01 -t mem -w 2 -c 54 
    LXC lxctest01 WARNING - Used Memory: 2% (97 MB)|mem_used=101982208B;0;0;0;4294967296
    
    ./check_lxc.sh -n lxctest01 -t mem -w 85 -c 95 -u k
    LXC lxctest01 OK - Used Memory: 2% (98600 KB)|mem_used=100966400B;0;0;0;4294967296
    
    ./check_lxc.sh -n ALL -t auto 
    LXC AUTOSTART CRITICAL: lxctest01

    ./check_lxc.sh -n lxctest01 -t swap -w 50 -c 70
    LXC lxctest01 CRITICAL - Used Swap: 81 MB|swap=85680128B;52428800;73400320;0;0
 
    ./check_lxc.sh -n lxctest01 -t cpu -w 80 -c 90
    LXC lxctest01 OK - CPU Usage: 27%|cpu=27%;80;90;0;0
 

Enable cgroup memory for memory check
------------------------------------
To be able to run the memory check (-t mem), the cgroup subsys "memory" must be enabled. You can verify this manually by running:

    cat /proc/cgroups | grep memory
    
If the first value is not enabled (0), then add the following options as your kernel boot parameter: "cgroup_enable=memory" and "swapaccount=1". In Debian this can be done by modifying /etc/default/grub2 followed by a update of the grub2 and reboot:

    # cat /etc/default/grub | grep CMDLINE_LINUX_DEFAULT
    GRUB_CMDLINE_LINUX_DEFAULT="quiet cgroup_enable=memory swapaccount=1"
    
    update-grub2
    reboot

Then verify if you can get the memory statistics of a container:

    lxc-cgroup -n lxctest01 memory.stat
