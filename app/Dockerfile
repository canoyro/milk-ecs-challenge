FROM nginx:1.25-alpine

COPY index.template.html /usr/share/nginx/templates/index.template.html
COPY render-index.sh /docker-entrypoint.d/40-render-index.sh

RUN chmod +x /docker-entrypoint.d/40-render-index.sh
