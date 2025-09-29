# ---------------------------
# 1. Installer Stage
# ---------------------------
FROM node:20-bullseye AS installer

COPY . /juice-shop
WORKDIR /juice-shop

# Install global tools
RUN npm i -g typescript ts-node

# Install production dependencies
RUN npm install --omit=dev --unsafe-perm && \
    npm dedupe

# Cleanup frontend cache
RUN rm -rf frontend/node_modules frontend/.angular frontend/src/assets

# Prepare logs directory
RUN mkdir logs && \
    chown -R 65532 logs && \
    chgrp -R 0 ftp/ frontend/dist/ logs/ data/ i18n/ && \
    chmod -R g=u ftp/ frontend/dist/ logs/ data/ i18n/

# Remove optional data
RUN rm data/chatbot/botDefaultTrainingData.json || true && \
    rm ftp/legal.md || true && \
    rm i18n/*.json || true

# Install CycloneDX and generate SBOM
ARG CYCLONEDX_NPM_VERSION=latest
RUN npm install -g @cyclonedx/cyclonedx-npm@$CYCLONEDX_NPM_VERSION && \
    npm run sbom


# ---------------------------
# 2. Libxmljs Builder Stage
# ---------------------------
FROM node:20-bullseye AS libxmljs-builder

WORKDIR /juice-shop

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    python3 \
 && rm -rf /var/lib/apt/lists/*

COPY --from=installer /juice-shop/node_modules ./node_modules

# Rebuild libxmljs2 to fix startup error
RUN rm -rf node_modules/libxmljs2/build && \
    cd node_modules/libxmljs2 && \
    npm run build


# ---------------------------
# 3. Final Stage
# ---------------------------
FROM gcr.io/distroless/nodejs20-debian11

ARG BUILD_DATE
ARG VCS_REF

FROM gcr.io/distroless/nodejs20-debian11

ARG BUILD_DATE
ARG VCS_REF

# Labels baked into the image
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.version="1.0.0"
LABEL org.opencontainers.image.source="https://github.com/esabou/juice-shop-goof"
LABEL io.snyk.containers.image.dockerfile="./Dockerfile"
LABEL org.opencontainers.image.created=$BUILD_DATE
LABEL org.opencontainers.image.revision=$VCS_REF


WORKDIR /juice-shop

COPY --from=installer --chown=65532:0 /juice-shop .
COPY --from=libxmljs-builder --chown=65532:0 /juice-shop/node_modules/libxmljs2 ./node_modules/libxmljs2

USER 65532
EXPOSE 3000

CMD ["/juice-shop/build/app.js"]
