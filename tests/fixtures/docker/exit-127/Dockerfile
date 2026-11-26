ARG BASE=busybox:1.37
FROM ${BASE}
RUN mkdir -p /www && echo ok > /www/index.html
USER 10001:10001
EXPOSE 8080
CMD ["httpdx", "-f", "-p", "0.0.0.0:8080"]
