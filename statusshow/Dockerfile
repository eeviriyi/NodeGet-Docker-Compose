FROM node:22-alpine AS build

ARG STATUSSHOW_REPO=https://github.com/NodeSeekDev/NodeGet-StatusShow.git
ARG STATUSSHOW_REF=main
ARG STATUSSHOW_SOURCE_REV=unknown

RUN apk add --no-cache git
WORKDIR /src
RUN echo "StatusShow source revision: ${STATUSSHOW_SOURCE_REV}" \
    && git clone --depth 1 --branch "${STATUSSHOW_REF}" "${STATUSSHOW_REPO}" . \
    && if [ "${STATUSSHOW_SOURCE_REV}" != "unknown" ]; then test "$(git rev-parse HEAD)" = "${STATUSSHOW_SOURCE_REV}"; fi
RUN npm ci
RUN npm run build

FROM nginx:1.27-alpine
COPY --from=build /src/dist/ /usr/share/nginx/html/
COPY nginx.conf /etc/nginx/conf.d/default.conf
