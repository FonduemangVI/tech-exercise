# tasky (Go web app). Base images come from ACR only: they are copied in
# with az acr import, so builds never pull from Docker Hub and the
# allowed-images policy can stay a simple "ACR only". No "# syntax=" line:
# it would fetch the BuildKit frontend image from Docker Hub on every build,
# and nothing here needs more than the frontend built into Docker.
#
#   docker build --build-arg REGISTRY=<acr>.azurecr.io -t <acr>.azurecr.io/tasky:<tag> app

# The default is a placeholder: .invalid is a reserved name (RFC 2606), so
# a build without --build-arg REGISTRY fails at the pull rather than
# fetching an image from anywhere else. It also keeps the default base
# image names valid, which BuildKit's lint checks (InvalidDefaultArgInFrom).
ARG REGISTRY=registry.invalid
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
