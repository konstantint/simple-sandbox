FROM ubuntu:22.04
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    squid-openssl iptables iproute2 openssl ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]