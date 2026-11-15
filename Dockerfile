# Gemhalla staging image: the server (game + admin page + WebSockets) with the browser build.
# The game is exported on the host first (Godot isn't in the image): tools/export_web.ps1,
# or just tools/run_docker.ps1, which exports when needed and starts docker compose.

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY server/GemhallaServer.csproj server/
RUN dotnet restore server/GemhallaServer.csproj
COPY server/ server/
# Windows build output (obj/ points NuGet at Visual Studio's folders) must not reach the
# Linux build, even if a build context leaks it in; restore again after clearing it.
RUN rm -rf server/bin server/obj && dotnet restore server/GemhallaServer.csproj
RUN dotnet publish server/GemhallaServer.csproj -c Release -o /out --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
COPY --from=build /out .
COPY build/web/ game/
# Sessions live on a volume so they survive rebuilds; the app user must own it.
RUN mkdir /data && chown $APP_UID /data
USER $APP_UID
ENV Url=http://+:8080 \
    HTTP_PORTS= \
    GameDir=/app/game \
    DataDir=/data \
    DOTNET_NOLOGO=1
VOLUME /data
EXPOSE 8080
ENTRYPOINT ["dotnet", "GemhallaServer.dll"]
