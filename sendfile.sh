#!/bin/bash
#Author @zhamrock
# Usage: ./scp_to_hosts.sh /path/to/file username

if [ $# -ne 2 ]; then
    echo "Usage: $0 <file_to_copy> <username>"
    exit 1
fi

FILE="$1"
USERNAME="$2"
DEST_DIR="/home/jhojo"

# Check file exists
if [ ! -f "$FILE" ]; then
    echo "Error: File $FILE does not exist."
    exit 1
fi

# Prompt for password ONCE (hidden input)
echo -n "Enter password for $USERNAME: "
read -s PASSWORD
echo ""

# Loop through hosts.txt
while read -r NAME IP; do
    echo "Copying to $NAME ($IP)..."

    sshpass -p "$PASSWORD" scp \
        -o PubkeyAuthentication=no \
        -o StrictHostKeyChecking=no \
        "$FILE" "$USERNAME@$IP:$DEST_DIR"

    if [ $? -eq 0 ]; then
        echo "✔ Success: $NAME ($IP)"
    else
        echo "✘ Failed:  $NAME ($IP)"
    fi

done < hosts.txt
