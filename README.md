# Simple Sandbox

Simple Sandbox is a Docker Compose template designed for sandboxing code execution (primarily intended to secure LLM agents or their tool invocations). Docker already provides isolation from the host system and allows one to limit which files the sandboxed code can access. The added nontrivial part in this example is the configuration of the sidecar Squid container, which intercepts all traffic leaving the sandbox container, and only passes requests based on a strict allowlist.

## Architecture

The Docker Compose stack consists of two main services:

1.  **sidecar_proxy:** An Ubuntu-based container running Squid and `iptables`. It acts as the network gateway for the sandbox.
2.  **sandbox:** The container where the agent or its tools actually run. It shares the network namespace of the `sidecar_proxy`. The example uses an `ubuntu` container, but pretty much
anything could be used here.

## Example usage

1.  **Start the sandbox:**
    ```bash
    docker compose up -d --build
    ```

2.  **Observe allowed access to Ubuntu domains:**
    Because `.ubuntu.com` is included in the `squid.conf` allowlist, the following commands succeed:
    ```bash
    docker exec sandbox apt update
    docker exec sandbox apt install -y curl
    docker exec sandbox curl -I https://ubuntu.com
    ```

3.  **Verify blocked access:**
    Because no other domains are allowed, this connection will be intercepted and denied by Squid:
    ```bash
    docker exec sandbox curl -I http://google.com
    ```
    You will receive a `403 Forbidden` response from the Squid proxy.
    Acesses to any ports besides 80, 443 and 53 (DNS) is blocked via `iptables` configuration in
    `proxy/entrypoint.sh`.

## Configuration

- **Allowlist:** Modify `squid-config/squid.conf` to add or remove allowed domains.
- **Volumes:** Update `docker-compose.yaml` to change which host directories are accessible to the agent.
- **Network:** Change the iptables commands in `proxy/endpoint.sh` to tweak network access rules.
- **CA Certificate:** The proxy generates a custom CA certificate at startup. This certificate is automatically mounted into the sandbox so that tools like `curl`, `apt`, and `node` can verify the intercepted SSL traffic.
