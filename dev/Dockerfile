# Linux dev environment mirroring nasa/spacewasm CI (.github/workflows/ci.yml),
# plus CMake — which upstream CI does not currently exercise.
FROM rust:1-bookworm

ARG WABT_VERSION=1.0.41

# 32-bit system libs (CI test-32bit job) + clang for wasm32-wasip1 test fixtures
RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      gcc-multilib \
      clang \
      lld \
      cmake \
      jq \
      wget \
      ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# aarch64 cross tools for cases/cross-guard/, which configures with F' toolchain
# files; helpers/arm-linux-base.cmake does find_program(... REQUIRED) for the C
# compiler, C++ compiler, assembler and ar, so all four have to be present.
#
# Deliberately a separate layer: apt cannot resolve these together with
# gcc-multilib in one transaction on bookworm, but installing them afterwards
# is fine.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      gcc-aarch64-linux-gnu \
      g++-aarch64-linux-gnu \
      binutils-aarch64-linux-gnu \
 && rm -rf /var/lib/apt/lists/*

# WABT — spectests shell out to wat2wasm; without it all 75 core tests fail instantly
RUN wget -q "https://github.com/WebAssembly/wabt/releases/download/${WABT_VERSION}/wabt-${WABT_VERSION}-linux-x64.tar.gz" -O /tmp/wabt.tar.gz \
 && tar -xzf /tmp/wabt.tar.gz -C /tmp \
 && cp /tmp/wabt-${WABT_VERSION}/bin/* /usr/local/bin/ \
 && rm -rf /tmp/wabt.tar.gz /tmp/wabt-${WABT_VERSION}

# Targets: 32-bit (CI matrix), aarch64 (cases/cross-guard/) and wasm32 (fixtures)
RUN rustup target add \
      i686-unknown-linux-gnu \
      aarch64-unknown-linux-gnu \
      wasm32-unknown-unknown \
      wasm32-wasip1 \
 && rustup component add rustfmt clippy

WORKDIR /work
