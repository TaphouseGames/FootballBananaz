# The match server as the host (Edgegap) runs it: Godot without a window, and
# the game as tools\build_server.bat packed it (build/server.pck).
#
# Build from the project's folder, after tools\build_server.bat:
#   docker build -f server/Dockerfile -t football-bananaz-server:<version> .
# One container plays one match and ends. It listens on UDP 24642 unless the
# host names another port (see scripts/net/net_host.gd).
FROM ubuntu:24.04
ARG GODOT_VERSION=4.7.2
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates wget unzip libfontconfig1 \
    && wget -q https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip -O /tmp/godot.zip \
    && unzip -q /tmp/godot.zip -d /tmp/godot \
    && mkdir /game \
    && mv /tmp/godot/Godot_v${GODOT_VERSION}-stable_linux.x86_64 /game/godot \
    && chmod +x /game/godot \
    && rm -rf /tmp/godot /tmp/godot.zip /var/lib/apt/lists/*
COPY build/server.pck /game/server.pck
WORKDIR /game
EXPOSE 24642/udp
CMD ["/game/godot", "--headless", "--main-pack", "/game/server.pck", "res://scenes/server.tscn", "--", "port=24642"]
