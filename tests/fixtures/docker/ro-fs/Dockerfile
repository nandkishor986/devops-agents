ARG BASE=busybox:1.37
FROM ${BASE}
RUN mkdir -p /www /data && echo ok > /www/index.html && chown 10001:10001 /data
USER 10001:10001
EXPOSE 8080
CMD ["sh", "-c", "echo started > /data/state && exec httpd -f -p 0.0.0.0:8080 -h /www"]
