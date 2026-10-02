# dcrd-mainnet (GitHub Container Registry)

[![Build and publish dcrd image](https://github.com/jzbz/dcrd-mainnet/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/jzbz/dcrd-mainnet/actions/workflows/docker-publish.yml)
[![ISC License](https://img.shields.io/badge/license-ISC-blue.svg)](https://copyfree.org)

A Docker image for running a [Decred](https://decred.org) full node
([`dcrd`](https://github.com/decred/dcrd)) on **mainnet**, published to the
**GitHub Container Registry** at `ghcr.io/jzbz/dcrd-mainnet`.

This is a community-maintained equivalent of the original
[`decred/dcrd-mainnet`](https://hub.docker.com/r/decred/dcrd-mainnet) image on
Docker Hub, updated to **dcrd v2.1.6**. The image is built straight from
Decred's own [official, security-hardened Docker
setup](https://github.com/decred/dcrd/tree/master/contrib/docker).

## What's inside

The image is built from source via a multi-stage build and the final image is
based on `scratch` (completely empty). It contains only the Decred binaries —
no shell, package manager, or anything else:

| Binary | Purpose |
| --- | --- |
| `dcrd` | The Decred full node daemon |
| `dcrctl` | RPC client for querying/controlling `dcrd` |
| `gencerts` | Generates the RPC TLS certificate |
| `promptsecret` | Helper for reading secrets |

Security properties:

- Runs as a **non-root** user with a static `UID:GID` of `10000:10000`
- `scratch`-based, so there's no shell or extra binaries for an attacker to use
- Statically linked binaries (`CGO_ENABLED=0`) compressed with `upx`

## Supported tags & architectures

- Tags: `latest`, `v2.1.6`, `2.1.6`
- Architectures: `linux/amd64`, `linux/arm64` (works on x86-64 servers and on
  ARM such as Raspberry Pi 4/5, Apple Silicon, and AWS Graviton)

## Quick start

The container defaults to running `dcrd` on **mainnet**.

### 1. Pull the image

```sh
docker pull ghcr.io/jzbz/dcrd-mainnet:latest
```

### 2. Create a data volume

The node runs as UID/GID `10000:10000`, so the volume must be owned by that id.

```sh
docker volume create decred-data
DECRED_DATA_VOLUME=$(docker volume inspect decred-data -f '{{.Mountpoint}}')
sudo chown -R 10000:10000 "${DECRED_DATA_VOLUME}"
```

### 3. Run the node

```sh
docker run -d --read-only \
  --name dcrd \
  -v decred-data:/home/decred \
  -p 9108:9108 \
  ghcr.io/jzbz/dcrd-mainnet:latest --altdnsnames dcrd
```

- `-p 9108:9108` exposes the mainnet peer-to-peer port so your node can accept
  inbound connections and help decentralize the network. Configure your host
  firewall / NAT port-forwarding accordingly.
- `--altdnsnames dcrd` adds the container name to the auto-generated RPC TLS
  certificate so remote RPC clients can authenticate. See
  [RPC notes](#rpc-access) below.

### 4. Watch the logs

```sh
docker logs -f dcrd
```

The node will begin downloading and validating the blockchain. This takes a
while on first run.

### 5. Stop / start

```sh
docker stop -t 60 dcrd   # allow up to 60s for a graceful shutdown
docker start dcrd
```

## Querying the node with `dcrctl`

`dcrctl` is bundled and pre-configured to talk to the local `dcrd` using its
credentials inside the data volume — no extra setup needed:

```sh
docker exec dcrd dcrctl getblockchaininfo
docker exec dcrd dcrctl getpeerinfo
docker exec dcrd dcrctl -l          # list available chain-server commands
```

## Docker Compose

A ready-to-use [`docker-compose.yml`](docker-compose.yml) is included:

```sh
docker compose up -d
docker compose logs -f
```

## Environment variables

| Variable | Default | Description |
| --- | --- | --- |
| `DECRED_DATA` | `/home/decred` | Data directory inside the container. |
| `DCRD_NO_FILE_LOGGING` | `true` | Log only to stdout (container best practice). Set to `false` to also write log files under `DECRED_DATA`. |
| `DCRD_ALT_DNSNAMES` | _none_ | Comma-separated alternate DNS names added to the RPC TLS certificate. Equivalent to the `--altdnsnames` flag. |

<a name="rpc-access"></a>
## RPC access

`dcrd` automatically generates a random `rpcuser`/`rpcpass` and a self-signed
TLS certificate on first run, stored in the data volume under `.dcrd/`. Local
authentication (running `dcrctl` inside the container, as above) works with no
configuration.

For **remote** RPC access (port `9109`), start the container with a stable name
and pass `--altdnsnames <name>` (or set `DCRD_ALT_DNSNAMES`) so the certificate
matches the hostname clients connect to, then publish the port with `-p
9109:9109`. The generated credentials and `rpc.cert` are inside the
`decred-data` volume under `.dcrd/`.

## Running testnet / simnet

The same image can run other networks by passing the relevant flag:

```sh
docker run -d --name dcrd-testnet -v decred-testnet-data:/home/decred \
  -p 19108:19108 ghcr.io/jzbz/dcrd-mainnet:latest --testnet --altdnsnames dcrd-testnet
```

Exposed ports: `9108`/`9109` (mainnet p2p/rpc), `19108`/`19109` (testnet),
`18555`/`19556` (simnet).

## Building locally

A [`Makefile`](Makefile) wraps the common Docker commands. Run `make help` to
see every target.

```sh
make build                 # build a local image for your host (dcrd v2.1.6)
make build VERSION=2.1.5   # build a different version
make run                   # create the data volume and start a node
make logs                  # follow the node logs
make ctl CMD=getblockchaininfo
make push                  # build multi-arch and push to the registry
```

Equivalent raw Docker commands, if you prefer:

```sh
docker build -t dcrd-mainnet .
docker build --build-arg DCRD_BUILD_TAG=release-v2.1.5 -t dcrd-mainnet .
```

## Publishing a new version

The [workflow](.github/workflows/docker-publish.yml) publishes to ghcr.io on
push to `master` and on version tags. Pull requests build the image (amd64
only) to validate changes but do not push. To cut a new release:

```sh
# Option A: push a git tag (recommended). Publishes :v2.1.7, :2.1.7, and :latest.
git tag v2.1.7 && git push origin v2.1.7

# Option B: run the workflow manually from the Actions tab, or via the CLI.
# Manual runs do NOT move :latest unless you pass mark_latest=true, so you can
# safely (re)build an older version without clobbering :latest.
gh workflow run docker-publish.yml -f dcrd_version=2.1.7 -f mark_latest=true
```

The Dockerfile's golang base image and the workflow's actions are kept current
by [Dependabot](.github/dependabot.yml). Dependabot keeps the golang tag's
`-alpineX.Y` suffix, so moving the builder to a newer Alpine release is a
manual edit of the `FROM` line (tag and digest).

## Credits & license

This image is built from [Decred's official `contrib/docker`
setup](https://github.com/decred/dcrd/tree/master/contrib/docker). `dcrd`,
`dcrctl`, and the entrypoint are works of The Decred developers, licensed under
the [ISC License](LICENSE). This repository is an independent packaging effort
and is not officially affiliated with the Decred project.
