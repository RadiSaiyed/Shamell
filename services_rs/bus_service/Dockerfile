FROM rust:1.93.0-slim-bookworm@sha256:776861219cd851131c1cec3bbd7cbeb16b99a794048097eb69ad9682a8ed0d57 AS builder

WORKDIR /app

# Build resilience defaults for constrained CI/hosts.
ENV CARGO_NET_RETRY=10 \
    CARGO_HTTP_TIMEOUT=600 \
    CARGO_BUILD_JOBS=2

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
  && rm -rf /var/lib/apt/lists/*

COPY Cargo.toml Cargo.lock /app/
COPY crates_rs /app/crates_rs
COPY services_rs /app/services_rs

RUN cargo build --release -p shamell_bus_service

FROM debian:bookworm-slim@sha256:98f4b71de414932439ac6ac690d7060df1f27161073c5036a7553723881bffbe

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
  && rm -rf /var/lib/apt/lists/*

# Run as non-root (defense-in-depth).
RUN groupadd --gid 10001 app && \
  useradd --uid 10001 --gid 10001 --create-home --home-dir /home/app --shell /usr/sbin/nologin app

COPY --from=builder /app/target/release/shamell_bus_service /usr/local/bin/shamell_bus_service

USER app:app

ENV APP_HOST=0.0.0.0 \
    APP_PORT=8083

EXPOSE 8083

CMD ["shamell_bus_service"]
