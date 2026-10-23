# Static application: no package installation, transpilation or development runtime needed.
FROM nginx/nginx-unprivileged:1.30.6-alpine3.24
ARG APP_VERSION=v1
COPY --chown=101:101 nginx-main.conf /etc/nginx/nginx.conf
COPY --chown=101:101 nginx.conf /etc/nginx/conf.d/default.conf
COPY --chown=101:101 dist/ /usr/share/nginx/html/
# An unknown version fails the build instead of silently falling back to another release.
COPY --chown=101:101 releases/${APP_VERSION}.json /usr/share/nginx/html/version.json
USER 101:101
EXPOSE 8888
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 CMD wget -q -O /dev/null http://127.0.0.1:8888/healthz || exit 1
CMD ["nginx", "-g", "daemon off;"]
