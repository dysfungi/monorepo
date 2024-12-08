####################### BUILD #######################
# https://hub.docker.com/r/microsoft/dotnet-sdk
# https://github.com/dotnet/dotnet-docker/blob/main/samples/README.md

FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:8.0-alpine AS build
ARG TARGETARCH
WORKDIR /source

# Copy project file and restore as distinct layers
COPY --link AutoMate/*.fsproj AutoMate/
RUN dotnet restore --arch $TARGETARCH ./AutoMate/AutoMate.fsproj

COPY --link . .
RUN dotnet publish --arch $TARGETARCH --no-restore --output /app ./AutoMate

####################### TESTS #######################
# https://github.com/dotnet/dotnet-docker/blob/main/samples/run-tests-in-sdk-container.md#running-tests-in-an-executable-stage

FROM build AS unit-test-build

COPY --link AutoMate.Tests/*.fsproj AutoMate.Tests/
WORKDIR /source/AutoMate.Tests
RUN dotnet restore

COPY --link AutoMate.Tests/ .
RUN dotnet build --no-restore

FROM unit-test-build AS unit-test

ENTRYPOINT ["dotnet", "test", "--no-build", "--logger:trx"]

####################### DEBUG #######################

FROM build AS debug

WORKDIR /source/AutoMate
EXPOSE 8080
ENTRYPOINT ["dotnet", "run", "--no-build", "--logger:trx"]

HEALTHCHECK \
  CMD curl --fail http://localhost:8080/-/alive || exit 1

####################### FINAL #######################
# https://hub.docker.com/r/microsoft/dotnet-aspnet/
# https://github.com/dotnet/dotnet-docker/blob/main/samples/aspnetapp/README.md
# https://github.com/dotnet/dotnet-docker/blob/main/samples/aspnetapp/Dockerfile

FROM mcr.microsoft.com/dotnet/aspnet:8.0-alpine AS final

RUN apk add curl
HEALTHCHECK \
  CMD curl --fail http://localhost:8080/-/alive || exit 1

EXPOSE 8080
WORKDIR /app
COPY --link --from=build /app .
USER $APP_UID
ENTRYPOINT ["./AutoMate"]
