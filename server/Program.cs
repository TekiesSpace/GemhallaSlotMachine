using GemhallaServer;
using Microsoft.AspNetCore.StaticFiles;
using Microsoft.Extensions.FileProviders;

// Gemhalla server: serves the browser build of the game, the admin page (/admin), and
// the WebSockets that connect them. Run it with tools/run_server.ps1.

var builder = WebApplication.CreateBuilder(args);
// Localhost only: nothing else on the network can reach the game or the admin page.
// The Docker image sets Url to listen inside the container (see Dockerfile).
builder.WebHost.UseUrls(builder.Configuration["Url"] ?? "http://localhost:8070");
builder.Services.AddSingleton<SessionHub>();
builder.AddAdminAuth();

var app = builder.Build();
// Admin page sign-in (AdminPassword setting); also handles "/admin" -> "/admin/".
app.UseAdminAuth();
app.UseWebSockets(new WebSocketOptions { KeepAliveInterval = TimeSpan.FromSeconds(20) });

// The game: Godot's web export (tools/export_web.ps1 writes it to build/web).
var gameDir = Path.GetFullPath(Path.Combine(app.Environment.ContentRootPath, builder.Configuration["GameDir"] ?? "../build/web"));
if (Directory.Exists(gameDir))
{
    var gameFiles = new PhysicalFileProvider(gameDir);
    var types = new FileExtensionContentTypeProvider();
    types.Mappings[".pck"] = "application/octet-stream";
    types.Mappings[".wasm"] = "application/wasm";
    app.UseDefaultFiles(new DefaultFilesOptions { FileProvider = gameFiles });
    app.UseStaticFiles(new StaticFileOptions
    {
        FileProvider = gameFiles,
        ContentTypeProvider = types,
        // Always check for a newer export, so a re-export shows up on reload.
        OnPrepareResponse = ctx => ctx.Context.Response.Headers.CacheControl = "no-cache",
    });
}
else
{
    app.Logger.LogWarning("No game build at {Dir}. Run tools/export_web.ps1 first.", gameDir);
}

// The admin page (wwwroot/admin), behind UseAdminAuth above.
app.UseDefaultFiles();
app.UseStaticFiles();

// The game asks for this at startup: an answer means it was served by this server and
// should connect; a static web host has no such path, so the game plays offline there.
app.MapGet("/gemhalla-server", () => Results.Text("gemhalla"));

app.Map("/ws/game", async (HttpContext context, SessionHub hub) =>
{
    if (!context.WebSockets.IsWebSocketRequest) { context.Response.StatusCode = 400; return; }
    using var socket = await context.WebSockets.AcceptWebSocketAsync();
    await hub.RunGameAsync(socket, context.RequestAborted);
});

app.Map("/ws/admin", async (HttpContext context, SessionHub hub) =>
{
    if (!context.WebSockets.IsWebSocketRequest) { context.Response.StatusCode = 400; return; }
    using var socket = await context.WebSockets.AcceptWebSocketAsync();
    await hub.RunAdminAsync(socket, context.RequestAborted);
});

app.Run();
