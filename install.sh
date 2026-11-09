#!/usr/bin/env bash
set -euo pipefail

fail() {
    printf 'Compose Control: %s\n' "$*" >&2
    exit 1
}

role=${1:-}
case "$role" in
    server) manifest=compose.yaml; service=compose-control; container_port=8080 ;;
    agent) manifest=compose.agent.yaml; service=compose-control-agent; container_port=5151 ;;
    *) fail 'Usage: bash install.sh server|agent' ;;
esac

[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] ||
    fail 'The published images require Linux x86-64. On Windows, run the PowerShell installer with Ubuntu on WSL 2.'
command -v curl >/dev/null || fail 'Install curl, then run the installer again.'

as_root() {
    if (( EUID == 0 )); then
        "$@"
    else
        command -v sudo >/dev/null || fail 'This step requires root or sudo.'
        sudo "$@"
    fi
}

install_docker() {
    [[ -r /etc/os-release ]] || fail 'Install Docker Engine and the Compose plugin for your Linux distribution, then run this command again.'
    . /etc/os-release
    case "${ID:-}" in
        ubuntu|debian) ;;
        *) fail 'Automatic Docker installation supports Ubuntu and Debian. Install Docker Engine and the Compose plugin for your distribution, then rerun.' ;;
    esac
    local codename=${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}
    [[ $codename =~ ^[a-z][a-z0-9-]*$ ]] || fail 'Could not determine the distribution codename for Docker packages.'
    if grep -qi microsoft /proc/sys/kernel/osrelease && [[ ! -d /run/systemd/system ]]; then
        fail 'Enable systemd in your WSL 2 distribution, restart WSL, then rerun the installer.'
    fi

    local docker_repo="https://download.docker.com/linux/$ID"
    printf 'Docker was not found. Installing Docker Engine and Compose from Docker’s %s package repository.\n' "$ID"
    as_root apt-get update
    as_root apt-get install -y ca-certificates
    as_root install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "$docker_repo/gpg" -o "$scratch/docker.asc"
    as_root install -m 0644 "$scratch/docker.asc" /etc/apt/keyrings/docker.asc
    as_root tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: $docker_repo
Suites: $codename
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/docker.asc
EOF
    as_root apt-get update
    as_root apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    if [[ -d /run/systemd/system ]]; then
        as_root systemctl enable --now docker
    fi
}

directory="compose-control-$role"
mkdir -p "$directory"
cd "$directory"
scratch=$(mktemp -d .install.XXXXXXXX)
trap 'rm -f -- "$scratch/docker.asc" "$scratch/$manifest" "$scratch/.env"; rmdir -- "$scratch"' EXIT

if ! command -v docker >/dev/null; then
    install_docker
fi

# The containers mount this socket, so the installer must use the same local engine.
docker_cli=(env -u DOCKER_HOST -u DOCKER_CONTEXT docker --host unix:///var/run/docker.sock)
if ! "${docker_cli[@]}" info >/dev/null 2>&1; then
    (( EUID != 0 )) && command -v sudo >/dev/null ||
        fail 'Start the local Docker daemon and verify access to /var/run/docker.sock.'
    docker_cli=(sudo "${docker_cli[@]}")
    "${docker_cli[@]}" info >/dev/null ||
        fail 'Start the local Docker daemon and verify access to /var/run/docker.sock.'
fi
"${docker_cli[@]}" compose version >/dev/null ||
    fail 'Docker is installed. Add the Docker Compose v2 plugin, then rerun the installer.'

release_files=https://raw.githubusercontent.com/stoxello/Compose-Control-Releases/main
if [[ ! -e $manifest ]]; then
    curl -fsSL "$release_files/$manifest" -o "$scratch/$manifest"
    ln -- "$scratch/$manifest" "$manifest" || [[ -f $manifest ]]
fi

if [[ $role == agent && ! -e .env ]]; then
    command -v openssl >/dev/null || fail 'Install openssl to generate the agent token, then rerun.'
    token=$(openssl rand -hex 32)
    (umask 077; printf 'COMPOSE_CONTROL_AGENT_TOKEN=%s\n' "$token" > "$scratch/.env")
    ln -- "$scratch/.env" .env || [[ -f .env ]]
fi

"${docker_cli[@]}" compose -f "$manifest" up -d

published=$("${docker_cli[@]}" compose -f "$manifest" port "$service" "$container_port" 2>/dev/null) || published=
published=${published%%$'\n'*}
host_port=${published##*:}
[[ $host_port =~ ^[0-9]+$ ]] || host_port='<published-port>'

printf '\nCompose Control %s started.\n' "$role"
printf 'Deployment directory: %s\n\n' "$PWD"
if [[ $role == server ]]; then
    printf '1. Open http://localhost:%s on the server.\n' "$host_port"
    printf '   From another machine, use your configured HTTPS address or http://SERVER_HOST:%s on a trusted network.\n' "$host_port"
    printf '   Replace SERVER_HOST with the server hostname or IP address.\n'
    printf '2. Complete the first-run wizard to create the administrator account, then sign in.\n'
    printf '3. Open Stacks or App catalog. To connect another Docker host, open Environments.\n'
else
    printf '1. In the server console, open Environments > Connect a Docker host.\n'
    printf '2. Enter a name and the endpoint http://AGENT_HOST:%s.\n' "$host_port"
    printf '   Replace AGENT_HOST with a hostname or IP address the server container can reach.\n'
    if [[ ${docker_cli[0]} != sudo && -n ${COMPOSE_CONTROL_AGENT_TOKEN:-} ]]; then
        printf '3. For Access token, use the COMPOSE_CONTROL_AGENT_TOKEN value you supplied in the shell.\n'
    else
        printf '3. For Access token, open "%s/.env" privately and copy the value of COMPOSE_CONTROL_AGENT_TOKEN.\n' "$PWD"
    fi
    printf '4. Choose Add environment, then select the new host in the environment selector.\n'
fi

if [[ $host_port == '<published-port>' ]]; then
    printf '\nReplace <published-port> with the host port from the ports section in %s.\n' "$manifest"
fi
printf '\nIf the service is unavailable, view its logs with:\n  cd %q &&' "$PWD"
printf ' %q' "${docker_cli[@]}" compose -f "$manifest" logs --tail=100
printf '\n'
