check_lxc
=========

Monitoring plugin to check LXC (Linux Container) 


Usage
-----
    ./check_lxc.sh -n container -t type [-u unit] [-w warning] [-c critical]
    
Options and check types explained
---------------------------------
    Options:
        -n name of container (or ALL for some types)
        -t type to check (see list below)
        [-u unit of output values (k|m|g)]
        [-w warning threshold (percent)]
        [-c critical threshold (percent)]
        
    Types:
        mem -> Check the memory usage of the given container
        swap -> Check the swap usage
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

    ./check_lxc.sh -n lxctest01 -t swap
    LXC app1-ewmon-prod OK - Used Swap: 0 MB|swap=0B;;;0;0
 
