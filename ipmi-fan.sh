#!/bin/bash

# minimaldrehzahl in %, die nicht unterschritten werden kann,
# auch wenn das system noch so kühl ist
MIN_RPM=30

# maximaldrehzal in %, die nicht überschritten werden kann
MAX_RPM=100

# zieltemperatur des systems, die bei maximaler last nicht überschritten werden soll
# wenn die temperatur trotz maximaler lüfterdrehzahl überschritten wird, wird alarm ausgelöst
AVG_TMP=55

# temperaturdifferenz, die eine reaktion der lüfterdrehzahl einleiten soll
RAMP_TMP=5

# drehzahldifferenz in % pro reaktion
RAMP_RPM=10

# check temps every ... seconds
MYLOOP=30

RETVAL=""

MYHOST=$(hostname)
MYDOMAIN=example.com

MYLOG=/var/log/ipmi-fan.log
MYLOCK=/var/run/ipmi-fan.lck
MYSENS=/tmp/core.sense

#
## functions #################################################################################
#
log_message()
{
	timestamp=$(date +%F-%H-%M-%S)
	echo "$timestamp $1"
}

get_system_temp()
{
    act_tmp=0
    num_cores=${#cores[@]}

    for i in "${cores[@]}"
    do
        act_tmp=$(($act_tmp+$i))
    done

    act_tmp=$(($act_tmp/$num_cores))
}

set_fan_rpm()
{
    act_rpm=$1

    if [ $act_rpm -gt $MAX_RPM ]; then act_rpm=$MAX_RPM; fi
    if [ $act_rpm -lt $MIN_RPM ]; then act_rpm=$MIN_RPM; fi

    dec_to_hex $act_rpm; act_rpm_hex=$RETVAL; RETVAL=""

    log_message "INFO  -- Temp $act_tmp, Set RPM to 0x$act_rpm_hex ($act_rpm%)"

    ipmitool raw 0x30 0x30 0x02 0xff 0x$act_rpm_hex >/dev/null 2>&1
}

alert_fan_rpm()
{
    if [ $cnt_alert -eq 0 ]; then

        mail -s "Temperature Alert $MYHOST ($1)" -a"From:$MYHOST \<$MYHOST@$MYDOMAIN\>" root < $MYSENS
        log_message "ERROR -- Temperature too high at 100% fan rpm. Sending alert."

    fi

    cnt_alert=$(($cnt_alert+1)); if [ $cnt_alert -eq $MYLOOP ]; then cnt_alert=0; fi
}

dec_to_hex()
{
    val_hex=( $(echo "obase=16; ibase=10; $1" | bc) )
    val_dec=( $(echo "obase=10; ibase=16; $val_hex" | bc) )

    if [ $1 -ne $val_dec ]; then

        log_message "ERROR -- Value conversion error, aborting."

        exit 1

    fi

    RETVAL=$val_hex
}

get_abs()
{
    val_dec=$1
    RETVAL=${val_dec#-}
}

#
## main ##########################################################################################
#

command -v bc 1>/dev/null 2>&1       || { echo >&2 "bc program required but not found, aborting."; exit 1; }
command -v mail 1>/dev/null 2>&1     || { echo >&2 "mail program required but not found, aborting."; exit 1; }
command -v sensors 1>/dev/null 2>&1  || { echo >&2 "sensors program required but not found, aborting."; exit 1; }
command -v ipmitool 1>/dev/null 2>&1 || { echo >&2 "ipmitool program required but not found, aborting."; exit 1; }

if [ -f "$MYLOCK" ]; then

    log_message "ERROR -- ipmi-fan may be called only once, aborting. $MYLOCK?"
    exit 2

fi

touch "$MYLOCK"

act_tmp=0
act_rpm=0
act_rpm_hex=0
val_dec=0
val_hex=0
num_cores=0
cnt_alert=0

# lüftersteuerung manuell
ipmitool raw 0x30 0x30 0x01 0x00 >/dev/null 2>&1

set_fan_rpm $MAX_RPM
sleep $MYLOOP

set_fan_rpm $MIN_RPM
sleep $MYLOOP

while true
do

    sensors | grep Core > $MYSENS

    # schneide string bei +-zeichen, zweites element beginnt mit temp, schneide bei .-zeichen, erstes element ist temp
    cores=( $(cut -d'+' -f2 $MYSENS | cut -d'.' -f1) )

    get_system_temp

    # nur wenn der temperaturunterschied überhaupt größer ist als RAMP_TMP, mach etwas
    delta_t=$(($act_tmp-$AVG_TMP))
    get_abs $delta_t

    if [ $RETVAL -ge $RAMP_TMP ]; then

        # das system ist mindestens RAMP_TMP wärmer als soll
        if [ $delta_t -gt 0 ]; then

            # wenn zu warm trotz max fan rpm
            if [ $act_rpm -eq $MAX_RPM ]; then

                alert_fan_rpm $delta_t

            fi

            # wenn noch nicht an der oberen grenze
            if [ $act_rpm -lt $MAX_RPM ]; then

                set_fan_rpm $(($act_rpm+$RAMP_RPM))

            fi


        fi

        # das system ist mindestens RAMP_TMP kühler als erwartet
        if [ $delta_t -lt 0 ]; then

            # wenn nicht schon an der unteren grenze
            if [ $act_rpm -gt $MIN_RPM ]; then

                set_fan_rpm $(($act_rpm-$RAMP_RPM))

            fi

        fi

    fi

    sleep $MYLOOP

done

# eof

