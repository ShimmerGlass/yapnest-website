# nginx-unprivileged, not plain nginx: it runs as a non-root user (uid 101) and listens on 8080, so the container
# needs no root and no capabilities, and the site is static so nothing else is asked of it. The proxy in front
# publishes it. 1.30.5-alpine, pinned by digest like the other images.
FROM nginxinc/nginx-unprivileged:1.30.5-alpine@sha256:15c994d10d6d78658721c3bcafff14cb281fba2a4bdf9d5ba92c416a472516e3 AS base


# The checks run as part of the build, so a failing check fails the image, and CI needs nothing but Docker. The
# stage brings its own node and nginx: the HTML validator, the link check, `nginx -t`, and a real nginx
# queried with curl. It is built on the image's own nginx, so the config is tested on the version it ships with.
FROM base AS test

USER root
RUN apk add --no-cache nodejs npm curl
WORKDIR /check
RUN npm install --no-audit --no-fund --no-save html-validate@11.16.2

COPY nginx.conf /etc/nginx/nginx.conf
COPY public /srv/site
COPY .htmlvalidate.json ./
COPY tests tests
RUN npx html-validate --config .htmlvalidate.json /srv/site \
    && node tests/links.mjs /srv/site \
    && nginx -t \
    && tests/smoke.sh \
    && touch /tested


FROM base

COPY nginx.conf /etc/nginx/nginx.conf
COPY public /srv/site
# Nothing is copied from the test stage but its verdict: this fails the build if the stage did not pass.
RUN --mount=type=bind,from=test,source=/tested,target=/tested true

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1
