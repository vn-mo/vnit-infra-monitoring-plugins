#!/bin/bash
#################################################################################
# Script:       check_hp_msm
# Author:       Michael Geschwinder (Maerkischer-Kreis)
# Description:  Plugin for Nagios to check Wireless Stations on a HP MSM Wireless Controller
#               device with SNMP (v3).
# History:
# 20131030      Created plugin (types: msmuptime, msmcpuuse, msmramuse, msmpermstorage, msmtempstorage, apstatus)
# 20131114      Fixed bug on timeout (returns unknown now)
# 20131118      Added debug parameter and large structure mode (timeout problem)
# 20260714      Refactored SNMPv1 (-C community) to SNMPv3 (-u/-l/-a/-A/-x/-X); renamed -l (large) to -L
#
#################################################################################################################
# Usage:        ./check_msm_wifi.sh -H host -u user -l level -a authProto -A authPass -x privProto -X privPass -t type [-w warning] [-c critical] [-D debug] [-L large]
##################################################################################################################

help="check_msm_wifi (c) 2013 Michael Geschwinder published under GPL license
\nUsage: ./check_msm_wifi.sh -H host -u user -l level -a authProto -A authPass -x privProto -X privPass -t type [-w warning] [-c critical] [-D debug] [-L large]
\nRequirements: snmpget, snmpwalk, awk, sed, grep\n
\nOptions: \t-H hostname\n\t\t-u SNMPv3 security user name\n\t\t-l SNMPv3 security level (noAuthNoPriv|authNoPriv|authPriv) [default: authPriv]\n\t\t-a SNMPv3 auth protocol (MD5|SHA) [default: SHA]\n\t\t-A SNMPv3 auth passphrase\n\t\t-x SNMPv3 privacy protocol (DES|AES) [default: AES]\n\t\t-X SNMPv3 privacy passphrase\n\t\t-D enable Debug messages\n\t\t-L large structure tweak. Less information but much faster (Icinga timeout problem)\n\t\t-t Type to check, see list below
\t\t-w Warning Threshold (optional)\n\t\t-c Critical Threshold (optional)\n
\nTypes:\t\tmsmuptime -> Checks the uptime of the msm controller (days)
\t\tmsmcpuuse -> Checks the CPU usage of the msm controller (%)
\t\tmsmramusage -> Checks the RAM usage of the msm controller (%)
\t\tmsmpermstorage -> Check the permanent storage usage of the msm controller (%)
\t\tmsmtempstorage -> Check the temporary storage usage of the msm controller (%)
\\t\\tapstatus -> Checks the status of the attached accesspoints (critical if one is down)
\\t\\tapclientcount -> Total number of clients connected across all APs\""

##########################################################
# Nagios exit codes and PATH
##########################################################
STATE_OK=0              # define the exit code if status is OK
STATE_WARNING=1         # define the exit code if status is Warning
STATE_CRITICAL=2        # define the exit code if status is Critical
STATE_UNKNOWN=3         # define the exit code if status is Unknown
PATH=$PATH:/usr/local/bin:/usr/bin:/bin # Set path


##########################################################
# Debug Ausgabe aktivieren
##########################################################
DEBUG=0

##########################################################
# SNMPv3 credentials (defaults)
##########################################################
secuser=""
seclevel="authPriv"
authproto="MD5"
authpass=""
privproto="DES"
privpass=""

##########################################################
# Large structure
##########################################################
large=0

##########################################################
# Debug output function
##########################################################
function debug_out {
        if [ $DEBUG -eq "1" ]
        then
                datestring=$(date +%d%m%Y-%H:%M:%S)
                echo -e $datestring DEBUG: $1
        fi
}

###########################################################
# Check if programm exist $1
###########################################################
function check_prog {
        if ! `which $1 1>/dev/null`
        then
                echo "UNKNOWN: $1 does not exist, please check if command exists and PATH is correct"
                exit ${STATE_UNKNOWN}
        else
                debug_out "OK: $1 does exist"
        fi
}

############################################################
# Check Script parameters and set dummy values if required
############################################################
function check_param {
        if [ ! $host ]
        then
                echo "No Host specified... exiting..."
                exit $STATE_UNKNOWN
        fi

        if [ -z "$secuser" ]
        then
                echo "No SNMPv3 user specified (-u)... exiting..."
                exit $STATE_UNKNOWN
        fi

        if [[ "$seclevel" == "authNoPriv" || "$seclevel" == "authPriv" ]]
        then
                if [ -z "$authpass" ]
                then
                        echo "Security level $seclevel requires -A (auth passphrase)... exiting..."
                        exit $STATE_UNKNOWN
                fi
        fi

        if [[ "$seclevel" == "authPriv" ]]
        then
                if [ -z "$privpass" ]
                then
                        echo "Security level authPriv requires -X (privacy passphrase)... exiting..."
                        exit $STATE_UNKNOWN
                fi
        fi

        if [ ! $type ]
        then
                echo "No check type specified... exiting..."
                exit $STATE_UNKNOWN
        fi
        if [ ! $warning ]
        then
                debug_out "Setting dummy warn value "
                warning=999
        fi
        if [ ! $critical ]
        then
                debug_out "Setting dummy critical value "
                critical=999
        fi
        if [ $large == 1 ]
        then
                debug_out "Running in large structure mode"
                outtext="$outtext\nLarge Structure mode!\n"
        fi
}



############################################################
# Get SNMP Value
############################################################
function get_snmp {
        oid=$1
        snmpret=$(snmpget -v3 \
                -u "$secuser" \
                -l "$seclevel" \
                -a "$authproto" -A "$authpass" \
                -x "$privproto" -X "$privpass" \
                -mALL "$host" "$oid" 2>/dev/null)
        if [ $? == 0 ]
        then
                echo $snmpret
        else
                exit $STATE_UNKNOWN
        fi
}

#################################################################################
# Display Help screen
#################################################################################
if [ "${1}" = "--help" -o "${#}" = "0" ];
       then
       echo -e "${help}";
       exit $STATE_UNKNOWN;
fi

################################################################################
# check if requiered programs are installed
################################################################################
for cmd in snmpget snmpwalk awk sed grep;do check_prog ${cmd};done;

################################################################################
# Get user-given variables
################################################################################
while getopts "H:u:l:a:A:x:X:t:w:c:o:DL" Input;
do
       case ${Input} in
       H)      host=${OPTARG};;
       u)      secuser=${OPTARG};;
       l)      seclevel=${OPTARG};;
       a)      authproto=${OPTARG};;
       A)      authpass=${OPTARG};;
       x)      privproto=${OPTARG};;
       X)      privpass=${OPTARG};;
       t)      type=${OPTARG};;
       w)      warning=${OPTARG};;
       c)      critical=${OPTARG};;
       o)      moid=${OPTARG};;
       D)      DEBUG=1;;
       L)      large=1;;
       *)      echo "Wrong option given. Please use -H host -u user -l level -a authProto -A authPass -x privProto -X privPass -t type [-w warn] [-c crit] [-D] [-L]"
               exit 1
               ;;
       esac
done

debug_out "Host=$host, User=$secuser, Level=$seclevel, Type=$type, Warning=$warning, Critical=$critical"

check_param



################################################################################
# Fixed SNMP OIDs
################################################################################
BASE=".1.3.6.1.4.1.8744"
APBASE="$BASE.5.23"
PERFBASE="$BASE.5.21.1.1"
# coDevWirIfStaNumberOfClient: currently associated clients per radio per AP
CLIENTBASE="$BASE.5.25.1.2.1.1.9"




#################################################################################
# Switch Case for different check types
#################################################################################
case ${type} in
#Controller uptime
msmuptime)
        set -e
        uptime=$(get_snmp $PERFBASE.1.0 )
        set +e
        # Extract raw timeticks (1/100 s), convert to minutes for numeric perfdata
        ticks_raw=$(echo $uptime | awk '{gsub(/[()]/,"",$4); print $4}')
        uptime_min=$((ticks_raw / 6000))
        uptime_human=$(echo $uptime | awk '{print $5}')
        debug_out "uptime: $uptime_human (${uptime_min} min)"
        perf="uptime=${uptime_min}min;$warning;$critical;0;"
        if [ $uptime_min -ge $critical ]
        then
                echo "CRITICAL: Uptime ${uptime_min} min ($uptime_human) is higher than $critical min |$perf"
                exit $STATE_CRITICAL
        elif [ $uptime_min -ge $warning ]
        then
                echo "WARNING: Uptime ${uptime_min} min ($uptime_human) is higher than $warning min |$perf"
                exit $STATE_WARNING
        else
                echo "OK: Uptime is ${uptime_min} min ($uptime_human) |$perf"
                exit $STATE_OK
        fi

;;


# CPU Use
msmcpuuse)
        set -e
        cpuuse=$(get_snmp $PERFBASE.5.0)
        cpuuse=$(echo $cpuuse | awk '{print $4}')
        set +e
        perf="cpu_usage=$cpuuse%;$warning;$critical;;"
        if [ $cpuuse -ge $critical ]
        then
                echo "CRITICAL: CPU usage $cpuuse% is higher than $critical% |$perf"
                exit $STATE_CRITICAL
        elif [ $cpuuse -ge $warning ]
        then
                echo "WARNING: CPU usage $cpuuse% is higher than $warning% |$perf"
                exit $STATE_WARNING
        else
                echo "OK: CPU usage is $cpuuse% |$perf"
                exit $STATE_OK
        fi
;;
# RAM Use
msmramuse)
        set -e
        ramtotal=$(get_snmp  $PERFBASE.9.0)
        ramtotal=$(echo $ramtotal | awk '{print $4}')
        ramfree=$(get_snmp  $PERFBASE.10.0)
        ramfree=$(echo $ramfree| awk '{print $4}')
        set +e
        ramuse=$(echo "$ramtotal-$ramfree" | bc -l)
        ramperc=$(echo "($ramuse/$ramtotal)*100" | bc -l)
        ramperc=$(echo $ramperc | awk '{printf("%d\n",$1 + 0.5)}')

        debug_out "Ram total: $ramtotal   ram free: $ramfree   ram use: $ramuse"
        debug_out "Ram percentage: $ramperc"

        perf="ram_usage=$ramperc%;$warning;$critical;0;100"
        if [ $ramperc -ge $critical ]
        then
                echo "CRITICAL: Ram Usage $ramperc% is higher then $critical% |$perf"
                exit $STATE_CRITICAL
        elif [ $ramperc -ge $warning ]
        then
                echo "WARNING: Ram Usage $ramperc% is higher then $warning% |$perf"
                exit $STATE_WARNING
        else
                echo "OK: Ram Usage is $ramperc% |$perf"
                exit $STATE_OK
        fi
;;
# Permanent Storage
msmpermstorage)
        set -e
        permstorage=$(get_snmp $PERFBASE.13.0)
        permstorage=$(echo $permstorage | awk '{print $4}')
        set +e
        perf="permstorage=$permstorage%;$warning;$critical;0;100"
        if [ $permstorage -ge $critical ]
        then
                echo "CRITICAL: Permament storage usage $permstorage% is higher then $critical% |$perf"
                exit $STATE_CRITICAL
        elif [ $permstorage -ge $warning ]
        then
                echo "WARNING: Permament storage usage $permstorage% is higher then $warning% |$perf"
                exit $STATE_WARNING
        else
                echo "OK: Permament storage usage is $permstorage% |$perf"
                exit $STATE_OK
        fi

;;


# Temporary Storage
msmtempstorage)
        set -e
        tempstorage=$(get_snmp $PERFBASE.14.0)
        tempstorage=$(echo $tempstorage | awk '{print $4}')
        set +e
        perf="tempstorage=$tempstorage%;$warning;$critical;0;100"
        if [ $tempstorage -ge $critical ]
        then
                echo "CRITICAL: Temporary storage usage $tempstorage% is higher then $critical% |$perf"
                exit $STATE_CRITICAL
        elif [ $tempstorage -ge $warning ]
        then
                echo "WARNING: Temporary storage usage $tempstorage% is higher then $warning% |$perf"
                exit $STATE_WARNING
        else
                echo "OK: Temporary storage usage is $tempstorage% |$perf"
                exit $STATE_OK
        fi

;;

apstatus)
offline=0
unknown=0
set -e
dummy=$(get_snmp $APBASE.1.2.1.1.3.1)
set +e
ap_cnt=$(snmpwalk -v3 \
        -u "$secuser" -l "$seclevel" \
        -a "$authproto" -A "$authpass" \
        -x "$privproto" -X "$privpass" \
        "$host" -Osq $APBASE.1.2.1.1.5 2>/dev/null | wc -l)

debug_out "Controller has $ap_cnt APs"

        for ((i=1;i<=$ap_cnt;i++));
        do
                #echo "STATE (7 running, 1 disconnected):"
                set -e
                state=$(get_snmp $APBASE.1.2.1.1.5.$i)
                set +e
                state=$(echo $state | awk '{print $4}')
                mac=$(get_snmp $APBASE.1.2.1.1.3.$i | grep -o "\ ..\ ..\ ..\ ..\ ..\ .." | sed 's/[ \t]//'  )
                location=$(get_snmp $APBASE.1.2.1.1.7.$i | awk '{print $4}')
                if [ ! $large == 1 ]
                then
                        serial=$(get_snmp $APBASE.1.2.1.1.2.$i | awk '{print $4}')
                        ip=$(get_snmp $APBASE.1.2.1.1.4.$i | awk '{print $4}')
                        name=$(get_snmp $APBASE.1.2.1.1.6.$i | awk '{print $4}')
                        #contact=$(get_snmp $APBASE.1.2.1.1.8.$i | awk '{print $4}')
                        #group=$(get_snmp $APBASE.1.2.1.1.9.$i | awk '{print $4}')
                        #connecttime=$(get_snmp $APBASE.1.2.1.1.10.$i | awk '{print $4}')
                else
                        serial=""
                        #mac=""
                        ip=""
                        name="Not available"
                        contact=""
                        group=""
                fi

                if [ $state == "7" ]
                then
                        debug_out "AP $i is online"
                        #outtext="$outtext\nAP: $name id ONLINE (serial:$serial, mac:\"$mac\", ip:$ip, location:$location, contact:$contact, group:$group"
                        outtext="$outtext\nAP: $name id ONLINE (serial:$serial, mac:\"$mac\", ip:$ip, location:$location"

                elif [ $state == "1" ]
                then
                        debug_out "AP $i is offline"

                        if [ $large = 1 ]
                        then
                                serial=$(get_snmp $APBASE.1.2.1.1.2.$i | awk '{print $4}')
                                mac=$(get_snmp $APBASE.1.2.1.1.3.$i | grep -o "\ ..\ ..\ ..\ ..\ ..\ .." | sed 's/[ \t]//'  )
                        fi

                        #outtext="$outtext\nAP: $name id OFFLINE (serial:$serial, mac:\"$mac\", ip:$ip, location:$location, contact:$contact, group:$group"
                        outtext="$outtext\nAP: $name id OFFLINE (serial:$serial, mac:\"$mac\", ip:$ip, location:$location"
                        ((offline++))
                else
                        debug_out "AP $i is in UNKNOWN state"
                        state="error"
                        ((unknown++))
                fi





        done
                aponline=$(( ap_cnt - offline - unknown ))
                perf="apoffline=$offline;$warning;$critical;0;$ap_cnt aponline=$aponline;;;0;$ap_cnt aptotal=$ap_cnt;;;0;"
                if [ $offline -ge $critical ]
                then
                        echo -e "CRITICAL: $offline out of $ap_cnt accesspoints is/are offline |$perf"
                        exit $STATE_CRITICAL
                elif [ $offline -ge $warning ]
                then
                        echo -e "WARNING: $offline out of $ap_cnt accesspoints is/are offline |$perf"
                        exit $STATE_WARNING
                elif [ $unknown -ge 1 ]
                then
                        echo -e "UNKNOWN: $unknown accesspoints are in unknown state |$perf"
                        exit $STATE_UNKNOWN
                else
                        echo -e "OK: all $ap_cnt accesspoints are online |$perf"
                        exit $STATE_OK
                fi

;;

# Total currently associated clients across all APs
# OID: coDevWirIfStaNumberOfClient (.5.25.1.2.1.1.9.<apIdx>.<radioIdx>)
apclientcount)
        outtext=""

        # Walk all radios of all APs, sum clients per AP and overall
        raw=$(snmpwalk -v3 \
                -u "$secuser" -l "$seclevel" \
                -a "$authproto" -A "$authpass" \
                -x "$privproto" -X "$privpass" \
                "$host" -Osq $CLIENTBASE 2>/dev/null)

        if [ -z "$raw" ]; then
                echo "UNKNOWN: no data from coDevWirIfStaNumberOfClient"
                exit $STATE_UNKNOWN
        fi

        # Sum clients per AP index, build per-AP output
        declare -A ap_clients
        while IFS= read -r line; do
                oid=$(echo "$line" | awk '{print $1}')
                val=$(echo "$line" | awk '{print $2}')
                apidx=$(echo "$oid" | awk -F. '{print $(NF-1)}')
                ap_clients[$apidx]=$(( ${ap_clients[$apidx]:-0} + val ))
        done <<< "$raw"

        total_clients=0
        for apidx in $(echo "${!ap_clients[@]}" | tr ' ' '\n' | sort -n); do
                cnt=${ap_clients[$apidx]}
                total_clients=$((total_clients + cnt))
                ap_name=$(get_snmp $APBASE.1.2.1.1.6.$apidx 2>/dev/null | awk '{print $4}')
                outtext="$outtext\nAP$apidx: $ap_name clients=$cnt"
                debug_out "AP$apidx $ap_name: $cnt clients"
        done

        ap_cnt=${#ap_clients[@]}
        perf="clients=$total_clients;$warning;$critical;0;"
        if [ $total_clients -ge $critical ]
        then
                echo -e "CRITICAL: $total_clients clients currently associated across $ap_cnt APs |$perf"
                echo -e "$outtext"
                exit $STATE_CRITICAL
        elif [ $total_clients -ge $warning ]
        then
                echo -e "WARNING: $total_clients clients currently associated across $ap_cnt APs |$perf"
                echo -e "$outtext"
                exit $STATE_WARNING
        else
                echo -e "OK: $total_clients clients currently associated across $ap_cnt APs |$perf"
                echo -e "$outtext"
                exit $STATE_OK
        fi

;;

*)
        echo -e "${help}";
        exit $STATE_UNKNOWN;

esac
