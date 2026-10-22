FROM node:24-bookworm-slim AS frontend
WORKDIR /src/Frontend
COPY Frontend/package*.json ./
RUN npm ci
COPY Frontend/ ./
RUN npm run build

FROM swift:6.4-bookworm AS backend
WORKDIR /src
COPY Package.swift Package.resolved ./
COPY Sources/ Sources/
COPY Tests/ Tests/
RUN swift build -c release --product aelab-server && swift build -c release --product aelab

FROM swift:6.4-bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends openssh-client ca-certificates && rm -rf /var/lib/apt/lists/* && useradd -m -u 10001 aelab
WORKDIR /opt/aelab
COPY --from=backend /src/.build/release/aelab-server /usr/local/bin/aelab-server
COPY --from=backend /src/.build/release/aelab /usr/local/bin/aelab
COPY --from=frontend /src/Frontend/dist/ /opt/aelab/public/
COPY Docs/Config/aelab.example.json /usr/local/config/aelab.example.json
ENV AELAB_HOME=/var/lib/aelab AELAB_PUBLIC=/opt/aelab/public AELAB_BIND=0.0.0.0 AELAB_PORT=2108
USER aelab
EXPOSE 2108
CMD ["aelab-server"]
