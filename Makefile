IMAGE   := genewang/kdtools
VERSION := 1.2.3

PLATFORMS := linux/amd64,linux/arm64
BUILDER   ?= $(shell docker buildx ls 2>/dev/null | grep -q '^desktop-linux' && echo desktop-linux || echo default)

.PHONY: build push

## build: build multi-arch image locally (no push)
build:
	docker buildx build \
		--builder $(BUILDER) \
		--platform $(PLATFORMS) \
		--tag $(IMAGE):$(VERSION) \
		--tag $(IMAGE):latest \
		.

## push: build multi-arch image and push to Docker Hub
push:
	docker buildx build \
		--builder $(BUILDER) \
		--platform $(PLATFORMS) \
		--tag $(IMAGE):$(VERSION) \
		--tag $(IMAGE):latest \
		--push \
		.
