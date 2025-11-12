#!/bin/bash
#Author: @zhamrock
#November 12 2025
# SSH Multi-Host Script
# Usage: ./ssh_hosts.sh [hosts_file]

# Default hosts file
HOSTS_FILE="${1:-hosts.txt}"

# Check if hosts file exists
if [ ! -f "$HOSTS_FILE" ]; then
    echo "Error: Hosts file '$HOSTS_FILE' not found!"
    echo ""
    echo "Please create a hosts file with the following format:"
    echo "server_name server_ip"
    echo ""
    echo "Example:"
    echo "webserver1 192.168.1.10"
    echo "database1 192.168.1.20"
    echo "appserver1 10.0.0.15"
    exit 1
fi

# Read hosts into arrays
declare -a names
declare -a ips

while IFS=' ' read -r name ip; do
    # Skip empty lines and comments
    [[ -z "$name" || "$name" =~ ^#.*$ ]] && continue
    names+=("$name")
    ips+=("$ip")
done < "$HOSTS_FILE"

# Check if any hosts were found
if [ ${#names[@]} -eq 0 ]; then
    echo "Error: No valid hosts found in '$HOSTS_FILE'"
    exit 1
fi

# Display menu
echo "====================================="
echo "Available Servers:"
echo "====================================="
for i in "${!names[@]}"; do
    printf "%2d) %-20s %s\n" $((i+1)) "${names[$i]}" "${ips[$i]}"
done
echo "====================================="
echo " 0) Exit"
echo "====================================="

# Get user selection
read -p "Select a server to SSH into (0-${#names[@]}): " selection

# Validate input
if ! [[ "$selection" =~ ^[0-9]+$ ]]; then
    echo "Error: Invalid input. Please enter a number."
    exit 1
fi

# Exit option
if [ "$selection" -eq 0 ]; then
    echo "Exiting..."
    exit 0
fi

# Check if selection is in range
if [ "$selection" -lt 1 ] || [ "$selection" -gt ${#names[@]} ]; then
    echo "Error: Selection out of range."
    exit 1
fi

# Get selected server (adjust for 0-based array index)
idx=$((selection-1))
selected_name="${names[$idx]}"
selected_ip="${ips[$idx]}"

echo ""
echo "Connecting to $selected_name ($selected_ip)..."
echo ""

# SSH to the selected server with username
ssh "jhojo@$selected_ip"
