#!/bin/bash
set -e

# --- 1. SSL & Directory Setup ---
CERT_HELPER="/usr/lib/squid/security_file_certgen"
SSL_DB="/var/lib/squid/ssl_db"
CERT_DIR="/etc/squid/ssl_cert"
CERT_FILE="$CERT_DIR/myCA.pem"

mkdir -p "$CERT_DIR" /var/lib/squid
if [ ! -f "$CERT_FILE" ]; then
    openssl req -new -newkey rsa:2048 -sha256 -days 365 -nodes -x509 \
        -keyout "$CERT_FILE" -out "$CERT_FILE" -subj "/CN=SquidProxy" 2>/dev/null
fi
chmod 644 "$CERT_FILE"
chown -R proxy:proxy "$CERT_DIR" /var/lib/squid
[ ! -d "$SSL_DB" ] && "$CERT_HELPER" -c -s "$SSL_DB" -M 4MB && chown -R proxy:proxy "$SSL_DB"

SQUID_UID=$(id -u proxy)

# --- 2. Dynamic Network Discovery ---
# Find the gateway IP and the local bridge subnet
GATEWAY_IP=$(ip route | grep default | awk '{print $3}')
SUBNET=$(ip route | grep eth0 | grep -v default | awk '{print $1}')

# --- 3. Kernel Tweaks ---
sysctl -w net.ipv4.conf.all.route_localnet=1
sysctl -w net.ipv4.ip_forward=1

# --- 4. Firewall Logic ---
echo "Applying Compatible Hardened Rules (Gateway: $GATEWAY_IP, Subnet: $SUBNET)..."

# Flush Filter tables
iptables -F
iptables -F OUTPUT

# A. IPv6: REJECT instead of DROP. 
# This tells curl/nslookup "No IPv6 here" immediately so they switch to IPv4.
ip6tables -F OUTPUT || true
ip6tables -A OUTPUT -j REJECT --reject-with icmp6-adm-prohibited || true

# B. Allow Loopback
iptables -A OUTPUT -o lo -j ACCEPT

# C. Allow Established (Replies)
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# D. Allow DNS (UDP/TCP 53) to ANY destination 
# (Docker sometimes routes 8.8.8.8 through the bridge IP first)
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# E. Allow communication with the Docker Gateway and Subnet
# This fixes the "Network unreachable" by allowing the app to see its router.
iptables -A OUTPUT -d "$GATEWAY_IP" -j ACCEPT
iptables -A OUTPUT -d "$SUBNET" -j ACCEPT

# F. Allow Squid User (The Proxy) to go out to the internet
iptables -A OUTPUT -m owner --uid-owner "$SQUID_UID" -j ACCEPT

# G. NAT Table: Intercept
iptables -t nat -F OUTPUT
iptables -t nat -A OUTPUT -p tcp --dport 80 -m owner ! --uid-owner "$SQUID_UID" -j REDIRECT --to-port 3129
iptables -t nat -A OUTPUT -p tcp --dport 443 -m owner ! --uid-owner "$SQUID_UID" -j REDIRECT --to-port 3130

# H. Allow the redirected traffic specifically
iptables -A OUTPUT -p tcp --dport 3129:3130 -j ACCEPT

# I. Final Lock
iptables -A OUTPUT -j DROP

echo "Firewall active. Starting Squid..."
exec /usr/sbin/squid -f /etc/squid/squid.conf -NYCd 1