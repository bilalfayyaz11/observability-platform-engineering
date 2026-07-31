FROM nginx:alpine

COPY index.html /usr/share/nginx/html/index.html
COPY health /usr/share/nginx/html/health
COPY default.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

HEALTHCHECK --interval=3s --timeout=3s --start-period=3s --retries=5   CMD wget -qO- http://127.0.0.1/health | grep -q status=healthy || exit 1
