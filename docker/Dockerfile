# syntax=docker/dockerfile:1.7
# Build: podman build -t ghcr.io/<owner>/rosbe-builder:<tag> -f docker/Dockerfile .

FROM ubuntu:24.04

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
        bison flex ccache cmake ninja-build python3 \
        gcc g++ make pkg-config \
        git wget curl xz-utils tar ca-certificates \
        libc6-dev \
    && rm -rf /var/lib/apt/lists/*

COPY rosbe-unix-bootstrap.sh /tmp/rosbe-bootstrap.sh
RUN mkdir -p /opt/rosbe && \
    HOME=/tmp INSTALL_ROOT=/opt/rosbe sh /tmp/rosbe-bootstrap.sh && \
    rm -f /tmp/rosbe-bootstrap.sh

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENV ROSBE_ROOT=/opt/rosbe \
    LLVM_MINGW_ROOT=/opt/rosbe/llvm-mingw \
    REACTOS_CLANG_LLVM_MINGW_ROOT=/opt/rosbe/llvm-mingw \
    PATH=/opt/rosbe/llvm-mingw/bin:/opt/rosbe/mingw-gcc/x86_64-w64-mingw32/bin:/opt/rosbe/mingw-gcc/i686-w64-mingw32/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
