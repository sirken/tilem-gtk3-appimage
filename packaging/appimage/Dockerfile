# Old, still-supported-toolchain base image so the resulting AppImage's
# glibc requirement stays low (glibc is backward- but not forward-compatible).
# Works with either `docker build` or `podman build`.
ARG BASE_IMAGE=ubuntu:20.04
FROM ${BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        autoconf \
        automake \
        libtool \
        pkg-config \
        libgtk-3-dev \
        libglib2.0-dev \
        gettext \
        autopoint \
        libusb-1.0-0-dev \
        libarchive-dev \
        curl \
        ca-certificates \
        rsync \
        file \
    && rm -rf /var/lib/apt/lists/*

COPY build-in-container.sh /build-in-container.sh
COPY tools.sha256sums /tools.sha256sums

ENTRYPOINT ["/build-in-container.sh"]
