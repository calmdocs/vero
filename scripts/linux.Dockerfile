# GTK4 and a virtual display, so the Linux example can run - and be watched -
# on a Mac.  Built by scripts/run-linux.sh.
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-gi gir1.2-gtk-4.0 libgtk-4-1 \
      xvfb x11vnc x11-utils imagemagick xauth ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
