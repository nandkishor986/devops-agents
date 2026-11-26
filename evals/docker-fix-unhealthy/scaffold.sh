#!/usr/bin/env bash
mkdir -p www && echo ok > www/index.html
cat > Dockerfile <<'D'
FROM busybox:1.37
COPY www /www
USER 10001:10001
EXPOSE 8080
HEALTHCHECK --interval=2s --timeout=2s --start-period=2s --retries=2 CMD ["curl", "-fsS", "http://127.0.0.1:8081/"]
CMD ["httpd", "-f", "-p", "127.0.0.1:8080", "-h", "/www"]
D
