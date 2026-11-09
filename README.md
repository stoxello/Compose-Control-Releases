# Compose Control

Compose Control is a self-hosted web console for Docker and Docker Compose. Use the **server** to manage its Docker host, then install an **agent** on each additional host you want to manage from the same console.

[Installation and usage guide](https://stoxello.github.io/Compose-Control-Releases/) · [Built-in app catalog](https://stoxello.github.io/Compose-Control-Releases/catalog.html)

## Before you start

- The published images run on Linux x86-64. The installers use the local Docker Engine and Docker Compose v2. If Docker is missing on Ubuntu or Debian, the installer sets up Docker's package repository and installs Docker Engine and Compose using root or `sudo`. On other Linux distributions, install Docker Engine and Compose v2 first. If you already have Docker without Compose, add the [Compose plugin](https://docs.docker.com/compose/install/linux/).
- Bash and `curl` are required on the Linux host. The agent also uses `openssl` to generate its token. Use the PowerShell commands from PowerShell on Linux or Windows.
- On Windows, install [Ubuntu on WSL 2](https://learn.microsoft.com/en-us/windows/wsl/install) with [systemd](https://learn.microsoft.com/en-us/windows/wsl/systemd), then run the PowerShell command. It installs inside Ubuntu's Linux home directory. If another machine needs to reach a WSL-hosted server or agent, configure [WSL networking](https://learn.microsoft.com/en-us/windows/wsl/networking) for the relevant port.
- Both containers mount the Docker socket and can administer their host. Restrict access to trusted networks or a VPN. Use HTTPS for the console when accessing it over the network, and keep the agent port accessible only to the server.

## Install the server

Run one of these commands on the host that will run the web console. The installer creates `compose-control-server/` and uses the [server Compose file](compose.yaml).

**Bash**

```sh
(installer=$(mktemp) && trap 'rm -f -- "$installer"' EXIT && curl -fsSL https://raw.githubusercontent.com/stoxello/Compose-Control-Releases/main/install.sh -o "$installer" && bash "$installer" server)
```

**PowerShell**

```powershell
& ([scriptblock]::Create((Invoke-RestMethod 'https://raw.githubusercontent.com/stoxello/Compose-Control-Releases/main/install.ps1' -ErrorAction Stop))) server
```

On the server itself, open `http://localhost:8080`. From another machine on a trusted network, use `http://SERVER_HOST:8080` for initial setup, or use your HTTPS address if configured. Complete the first-run wizard to create the administrator account and sign in.

## Install an agent

Run one of these commands on the additional Docker host. The installer creates `compose-control-agent/`, downloads the [agent Compose file](compose.agent.yaml), and creates a private `.env` containing a random token. Re-running the installer reuses existing Compose files and tokens.

**Bash**

```sh
(installer=$(mktemp) && trap 'rm -f -- "$installer"' EXIT && curl -fsSL https://raw.githubusercontent.com/stoxello/Compose-Control-Releases/main/install.sh -o "$installer" && bash "$installer" agent)
```

**PowerShell**

```powershell
& ([scriptblock]::Create((Invoke-RestMethod 'https://raw.githubusercontent.com/stoxello/Compose-Control-Releases/main/install.ps1' -ErrorAction Stop))) agent
```

1. In the server console, open **Environments** and find **Connect a Docker host**.
2. Enter a name and the agent address, such as `http://AGENT_HOST:5151`. Use an address reachable from the server container.
3. Open the agent's `compose-control-agent/.env` privately and paste the value of `COMPOSE_CONTROL_AGENT_TOKEN` into **Access token**. Choose **Add environment**.
4. Switch to the new host using the environment selector at the top of the console. Choose **This host** to return to the server's local Docker engine.

You can review both installers before running them. [Bash](install.sh) · [PowerShell](install.ps1)

## Work with stacks

- Open **Stacks** to see Compose projects on the selected host. Create a stack from a Compose definition or choose a template in the app catalog.
- To deploy your own stack, select the target environment first, then provide a name, a Compose definition, and any required environment variables.
- Open a stack to inspect its containers and manage its lifecycle. Compose Control can edit stack files for managed stacks where editing is available. Removing a managed stack can delete its saved Compose files.
- Open **Containers** to inspect running workloads and read logs.

## Configure and update

You can also download either Compose file and run `docker compose -f FILE up -d` from its installation directory. For a manual agent installation, set `COMPOSE_CONTROL_AGENT_TOKEN` to a strong random value in a private `.env` beside the manifest before starting it.

| Setting in the installation directory's `.env` | Default or purpose |
| --- | --- |
| `COMPOSE_CONTROL_PORT` | Server host port, defaults to `8080` |
| `COMPOSE_CONTROL_IMAGE` | Server image, defaults to `ghcr.io/stoxello/compose-control:latest` |
| `COMPOSE_CONTROL_AGENT_PORT` | Agent host port, defaults to `5151` |
| `COMPOSE_CONTROL_AGENT_IMAGE` | Agent image, defaults to `ghcr.io/stoxello/compose-control-agent:latest` |
| `COMPOSE_CONTROL_AGENT_TOKEN` | Required shared secret for the agent |
| `COMPOSE_CONTROL_AGENT_STACKS_ROOT` | Absolute path for agent-managed stacks, defaults to `/opt/compose-control/stacks` |

From the corresponding installation directory, pull and recreate the service:

```sh
# Server
docker compose -f compose.yaml pull && docker compose -f compose.yaml up -d

# Agent
docker compose -f compose.agent.yaml pull && docker compose -f compose.agent.yaml up -d
```

Back up the server's `data/`, `keys/`, and `stacks/`. For an agent, preserve its `.env`, `agent-replicas/`, `agent-docker-config/`, and stacks root. These locations hold Compose Control state. Back up the data volumes and bind mounts used by your deployed apps separately.

## Troubleshooting

- **Server unavailable** · Confirm the configured port and run `docker compose -f compose.yaml logs --tail=100` from the server directory.
- **Agent unreachable** · Check `http://AGENT_HOST:5151/health` from the server's network. If the agent won't start, run `docker compose -f compose.agent.yaml logs --tail=100` from the agent directory and check that its `.env` contains a token.
- **Agent authentication fails** · Check that the console uses the current token from the agent's `.env`. Keep the token out of support requests and screenshots.
