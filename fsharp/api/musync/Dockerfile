####################### BUILD #######################
# https://hub.docker.com/r/microsoft/dotnet-sdk
# https://github.com/dotnet/dotnet-docker/blob/main/samples/README.md

FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:9.0-alpine AS build
ARG TARGETARCH
WORKDIR /source

# Copy project file and restore as distinct layers
COPY --link Musync/*.fsproj Musync/
RUN dotnet restore --arch $TARGETARCH ./Musync/Musync.fsproj

COPY --link . .
RUN dotnet publish --arch $TARGETARCH --no-restore --output /app ./Musync

####################### TESTS #######################
# https://github.com/dotnet/dotnet-docker/blob/main/samples/run-tests-in-sdk-container.md#running-tests-in-an-executable-stage

FROM build AS unit-test-build

COPY --link Musync.Tests/*.fsproj Musync.Tests/
WORKDIR /source/Musync.Tests
RUN dotnet restore

COPY --link Musync.Tests/ .
RUN dotnet build --no-restore

FROM unit-test-build AS unit-test

ENTRYPOINT ["dotnet", "test", "--no-build", "--logger:trx"]

####################### FINAL #######################
# https://github.com/dotnet/dotnet-docker/blob/main/samples/dotnetapp/Dockerfile
# musync is a CLI (Argu subcommands), not a web host — no HEALTHCHECK/port.

FROM mcr.microsoft.com/dotnet/runtime:9.0-alpine AS final

WORKDIR /app
COPY --link --from=build /app .
USER $APP_UID
ENTRYPOINT ["./Musync"]
