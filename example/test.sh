source cabletest_api.sh

# Set the packet size to 1024 bytes (i.e., 16 * 64-bytes per cycle)
set_cycles_per_packet 16

# Find out how many data-cycles are in a packet
cycles_per_packet=$(get_cycles_per_packet)

# Compute the size of packet in bytes
packet_size=$((cycles_per_packet * 64))

# Convert gigabytes to bytes
xfer_size=$(($1 * 1024 * 1024 * 1024))

# Compute the number of packets we're going to transfer
xfer_packets=$((xfer_size / packet_size))

# Start transferring packets
start $xfer_packets

percent=0
prior_rcvd=-1
rcvd_sequence=0;

printf "%15i total packets in task\n" $xfer_packets
while [ $percent -ne 100 ]; do
    
    if [ $(is_halted) -eq 3 ] ; then
        echo 
        echo "Halted by user" 1>&2
        exit 1
    fi

    # Find out how many packets we've received
    packets_rcvd=$(get_packets_rcvd)

    # Keep track of whether $packets_rcvd is changing
    if [ $packets_rcvd -ne $prior_rcvd ]; then
        prior_rcvd=$packets_rcvd;
        rcvd_sequence=1
    else
        rcvd_sequence=$((rcvd_sequence + 1))
    fi

    # If data isn't flowing in, stop the job
    if [ $rcvd_sequence -eq 5 ]; then
        echo -e "\n\n"
        echo "Packet flow has stopped!"
        echo $(get_packets_rcvd 1) packets received on QSFP0
        echo $(get_packets_rcvd 2) packets received on QSFP1
        exit 1        
    fi

    # Find out how many errors have occured
    errors1=$(get_errors 1)
    errors2=$(get_errors 2)
    
    # Compute the percentage complete
    percent=$((100 * packets_rcvd / xfer_packets))

    # Display our progress
    printf "\r%15i  [%3i%%]  (%i,%i errors)" $packets_rcvd $percent $errors1 $errors2

    # Pause a moment so we don't slam the PCI bus
    sleep .5

done

# Make sure we get a linefeed at the end of our output
echo ""



