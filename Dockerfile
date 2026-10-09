# Generated allowlisted context only: make image. No repository/config COPY.
# Docker Official Images mirror; anonymous CI avoids Docker Hub's shared-IP quota.
FROM public.ecr.aws/docker/library/nginx:1.30.5-alpine@sha256:0985e772fb9f729e6fa0980da05fca5d9c468e870eed43071545afa9d2e27d94
COPY nginx/ /etc/nginx/
COPY site/ /usr/share/nginx/html/
USER 101:101
EXPOSE 8080 8443
HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1
ENTRYPOINT ["nginx"]
CMD ["-g", "daemon off;"]
