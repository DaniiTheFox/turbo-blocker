#!/bin/bash

# URL of the IP list
IP_LIST_URL="https://raw.githubusercontent.com/stamparm/ipsum/master/ipsum.txt"

# Name of the ipset set
IPSET_NAME="blocked_ips"

# Check if ipset is installed
if ! command -v ipset &> /dev/null; then
  echo "ipset is not installed. Please install it and try again."
  exit 1
fi

# Create or flush the ipset list
echo "Creating or resetting ipset list: $IPSET_NAME..."
sudo ipset destroy "$IPSET_NAME" 2>/dev/null
sudo ipset create "$IPSET_NAME" hash:ip -exist

# Download the list of IPs
echo "Fetching IP list from $IP_LIST_URL..."
curl -s "$IP_LIST_URL" -o /tmp/ipsum.txt

if [ $? -ne 0 ]; then
  echo "Failed to download IP list. Exiting."
  exit 1
fi

# Filter out IP addresses (ignoring comments) and prepare ipset restore format
echo "Processing IP list for bulk insertion..."
{
  echo "create $IPSET_NAME hash:ip family inet hashsize 1024 maxelem 65536"
  grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" /tmp/ipsum.txt | awk '{print "add '$IPSET_NAME' "$1}'
} > /tmp/ipset_restore.txt

# Bulk restore into ipset
echo "Loading IPs into ipset in bulk..."
sudo ipset restore < /tmp/ipset_restore.txt

# Add an iptables rule to block all IPs in the ipset list if not already added
if ! sudo iptables -C INPUT -m set --match-set "$IPSET_NAME" src -j DROP 2>/dev/null; then
  echo "Adding iptables rule to block IPs from ipset list..."
  sudo iptables -I INPUT -m set --match-set "$IPSET_NAME" src -j DROP
fi

# Cleanup temporary files
rm -f /tmp/ipsum.txt /tmp/ipset_restore.txt

echo "All IPs have been loaded into the ipset list and blocked."

curl -sSL "https://check.torproject.org/cgi-bin/TorBulkExitList.py?ip=$(curl icanhazip.com)" | sed '/^#/d' | while read IP; do
  ipset -q -A tor $IP
done

iptables -A INPUT -m set --match-set tor src -j DROP
