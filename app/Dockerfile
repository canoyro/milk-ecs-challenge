FROM nginx:1.25-alpine

ARG APP_VERSION=dev
ARG IMAGE_TAG=local

ENV APP_VERSION=${APP_VERSION}
ENV IMAGE_TAG=${IMAGE_TAG}

COPY index.template.html /usr/share/nginx/templates/index.template.html
COPY render-index.sh /docker-entrypoint.d/40-render-index.sh

RUN chmod +x /docker-entrypoint.d/40-render-index.sh
