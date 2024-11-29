####################### BUILD #######################

# https://hub.docker.com/r/microsoft/dotnet-sdk
# https://github.com/dotnet/dotnet-docker/blob/main/samples/README.md
FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:8.0-alpine AS build
ARG TARGETARCH
WORKDIR /source

# Copy project file and restore as distinct layers
COPY --link AutoMate/AutoMate.fsproj AutoMate/
RUN dotnet restore --arch $TARGETARCH ./AutoMate/AutoMate.fsproj

COPY --link . .
RUN dotnet publish --arch $TARGETARCH --no-restore --output /app ./AutoMate

####################### FINAL #######################

# https://hub.docker.com/r/microsoft/dotnet-aspnet/
# https://github.com/dotnet/dotnet-docker/blob/main/samples/aspnetapp/README.md
# https://github.com/dotnet/dotnet-docker/blob/main/samples/aspnetapp/Dockerfile
FROM mcr.microsoft.com/dotnet/aspnet:8.0-alpine
EXPOSE 8080
WORKDIR /app
COPY --link --from=build /app .
USER $APP_UID
ENTRYPOINT ["./AutoMate"]
