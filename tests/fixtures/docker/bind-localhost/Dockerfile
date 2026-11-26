ARG BASE=busybox:1.37
FROM ${BASE}
RUN mkdir -p /www && echo ok > /www/index.html
USER 10001:10001
EXPOSE 8080
HEALTHCHECK --interval=2s --timeout=2s --start-period=2s --retries=2 CMD ["wget", "-q", "--spider", "http://127.0.0.1:8080/"]
CMD ["httpd", "-f", "-p", "127.0.0.1:8080", "-h", "/www"]
