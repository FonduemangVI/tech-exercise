# syntax=docker/dockerfile:1
# tasky (Go web app). Base images come from ACR only: they are copied in
# with az acr import, so builds never pull from Docker Hub and the
# allowed-images policy can stay a simple "ACR only".
#
#   docker build --build-arg REGISTRY=<acr>.azurecr.io -t <acr>.azurecr.io/tasky:<tag> app

ARG REGISTRY
ARG GO_IMAGE=${REGISTRY}/base/golang:1.26-alpine3.24
ARG RUNTIME_IMAGE=${REGISTRY}/base/alpine:3.24

FROM ${GO_IMAGE} AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/tasky .

FROM ${RUNTIME_IMAGE}
# Non-root user; Alpine keeps a shell so `kubectl exec ... cat` works (R16)
RUN addgroup -S -g 10001 tasky && adduser -S -D -H -u 10001 -G tasky tasky
WORKDIR /app
COPY --from=build /out/tasky ./tasky
COPY assets ./assets
# R16: file with my name, baked into the image
COPY wizexercise.txt ./wizexercise.txt
USER 10001:10001
EXPOSE 8080
ENTRYPOINT ["/app/tasky"]
