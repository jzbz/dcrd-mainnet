# Makefile for building, running, and publishing the dcrd-mainnet image.
#
# Common usage:
#   make build              # build a local image for your host architecture
#   make run                # create the data volume (if needed) and run a node
#   make logs               # follow the node's logs
#   make ctl CMD=getinfo    # run a dcrctl command against the node
#   make push               # build multi-arch and push to the registry
#   make help               # list all targets
#
# Override any variable on the command line, e.g.:
#   make build VERSION=2.1.5
#   make push  IMAGE=ghcr.io/youruser/dcrd-mainnet

# ---- Configuration -------------------------------------------------------

# dcrd version to build. Maps to the git tag release-v$(VERSION).
VERSION     ?= 2.1.6
BUILD_TAG   ?= release-v$(VERSION)

# Image reference (without tag) to build/push.
IMAGE       ?= ghcr.io/jzbz/dcrd-mainnet

# Architectures for multi-arch (push) builds.
PLATFORMS   ?= linux/amd64,linux/arm64

# Local container / volume names used by the run helpers.
CONTAINER   ?= dcrd
DATA_VOLUME ?= decred-data

# Mainnet ports.
P2P_PORT    ?= 9108
RPC_PORT    ?= 9109

DOCKER      ?= docker

# ---- Help ----------------------------------------------------------------

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z0-9_-]+:.*##' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

.PHONY: version
version: ## Print the resolved build variables
	@echo "VERSION   = $(VERSION)"
	@echo "BUILD_TAG = $(BUILD_TAG)"
	@echo "IMAGE     = $(IMAGE)"
	@echo "PLATFORMS = $(PLATFORMS)"

# ---- Build ---------------------------------------------------------------

.PHONY: build
build: ## Build a single-arch image for the local host
	$(DOCKER) build \
		--build-arg DCRD_BUILD_TAG=$(BUILD_TAG) \
		-t $(IMAGE):$(VERSION) -t $(IMAGE):latest .

.PHONY: buildx
buildx: ## Build a multi-arch image (no push; requires a buildx builder)
	$(DOCKER) buildx build --platform $(PLATFORMS) \
		--build-arg DCRD_BUILD_TAG=$(BUILD_TAG) \
		-t $(IMAGE):$(VERSION) -t $(IMAGE):latest .

.PHONY: push
push: ## Build a multi-arch image and push it to the registry
	$(DOCKER) buildx build --platform $(PLATFORMS) \
		--build-arg DCRD_BUILD_TAG=$(BUILD_TAG) \
		-t $(IMAGE):$(VERSION) -t $(IMAGE):latest --push .

# ---- Run -----------------------------------------------------------------

.PHONY: volume
volume: ## Create the data volume owned by the in-container UID:GID 10000
	-$(DOCKER) volume create $(DATA_VOLUME)
	$(DOCKER) run --rm -v $(DATA_VOLUME):/data busybox chown -R 10000:10000 /data

.PHONY: run
run: volume ## Run a mainnet node in the background
	$(DOCKER) run -d --read-only \
		--name $(CONTAINER) \
		-v $(DATA_VOLUME):/home/decred \
		-p $(P2P_PORT):$(P2P_PORT) \
		$(IMAGE):latest --altdnsnames $(CONTAINER)

.PHONY: logs
logs: ## Follow the node logs
	$(DOCKER) logs -f $(CONTAINER)

.PHONY: ctl
ctl: ## Run a dcrctl command, e.g. make ctl CMD="getblockchaininfo"
	$(DOCKER) exec $(CONTAINER) dcrctl $(CMD)

.PHONY: stop
stop: ## Stop the node (allowing up to 60s for a graceful shutdown)
	$(DOCKER) stop -t 60 $(CONTAINER)

.PHONY: start
start: ## Start a previously stopped node
	$(DOCKER) start $(CONTAINER)

.PHONY: rm
rm: ## Stop and remove the node container
	-$(DOCKER) stop -t 60 $(CONTAINER)
	-$(DOCKER) rm $(CONTAINER)

# ---- Compose -------------------------------------------------------------

.PHONY: up
up: ## Start the node via docker compose
	$(DOCKER) compose up -d

.PHONY: down
down: ## Stop the node started via docker compose
	$(DOCKER) compose down

# ---- Cleanup -------------------------------------------------------------

.PHONY: clean
clean: rm ## Remove the container and the locally built images
	-$(DOCKER) image rm $(IMAGE):$(VERSION) $(IMAGE):latest
