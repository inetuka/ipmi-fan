DELL Fan Control Mitigation

This file is public domain and provided as-is. There are NO guarantees. Use at your own risk.

This script was created after discovering a non-reaction of the cooling system (fan rpm) to load conditions.
(overheating, clock step-down, ...)

Preparations:
```
modprobe ipmi_msghandler
modprobe ipmi_devintf
modprobe ipmi_si
lsmod | grep ipmi
```
if success add modules to /etc/modules
```
apt-get install ipmitool lm-sensors
sensors-detect
sensors
```
check output of sensors for at least one line with core temp
```
ipmitool -I open sensors
```
check output of ipmitool for correct function

Best regards

Udo
