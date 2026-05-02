FROM node:22-alpine AS build

ARG STATUSSHOW_REPO=https://github.com/eeviriyi/NodeGet-StatusShow.git
ARG STATUSSHOW_REF=main

RUN apk add --no-cache git
WORKDIR /src
RUN git clone --depth 1 --branch "${STATUSSHOW_REF}" "${STATUSSHOW_REPO}" .
RUN npm ci
RUN npm run build

FROM nginx:1.27-alpine
COPY --from=build /src/dist/ /usr/share/nginx/html/
COPY nginx.conf /etc/nginx/conf.d/default.conf

