FROM rust:1.85-bookworm AS source

WORKDIR /src
COPY Cargo.toml Cargo.lock ./
COPY src/ src/

FROM source AS test
RUN cargo test --locked

FROM source AS build
ARG TARGET=aarch64-unknown-linux-musl
RUN rustup target add "$TARGET"
RUN RUSTFLAGS="-C linker=rust-lld" cargo build --locked --release --target "$TARGET" \
    && install -D -m 0755 "target/$TARGET/release/fbi" /out/fbi

FROM scratch
COPY --from=build /out/fbi /fbi
