using System.Net;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.HttpOverrides;

namespace GemhallaServer;

/// <summary>
/// Guards the admin page (/admin) and its WebSocket (/ws/admin).
/// With an AdminPassword set, you sign in at /admin/login and get a cookie (12 hours,
/// renewed while you use it). Without one, the admin page only answers on this PC
/// (localhost), which is how tools/run_server.ps1 runs it.
/// </summary>
public static class AdminAuth
{
    private const string LoginPath = "/admin/login";
    private const string LoginLimiter = "admin-login";

    public static void AddAdminAuth(this WebApplicationBuilder builder)
    {
        builder.Services
            .AddAuthentication(CookieAuthenticationDefaults.AuthenticationScheme)
            .AddCookie(options =>
            {
                options.Cookie.Name = "gemhalla_admin";
                options.Cookie.HttpOnly = true;
                // Strict: the cookie never rides along on another site's request or WebSocket.
                options.Cookie.SameSite = SameSiteMode.Strict;
                options.Cookie.SecurePolicy = CookieSecurePolicy.SameAsRequest;
                options.ExpireTimeSpan = TimeSpan.FromHours(12);
                options.SlidingExpiration = true;
                options.LoginPath = LoginPath;
            });

        // Keep the cookie-signing keys with the sessions, so a restart doesn't sign you out.
        var dataDir = SessionHub.ResolveDataDir(builder.Environment, builder.Configuration);
        builder.Services.AddDataProtection()
            .SetApplicationName("Gemhalla")
            .PersistKeysToFileSystem(new DirectoryInfo(Path.Combine(dataDir, "keys")));

        // Slow down password guessing: 10 tries a minute per address.
        builder.Services.AddRateLimiter(options =>
        {
            options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
            options.OnRejected = (context, token) =>
            {
                context.HttpContext.Response.ContentType = "text/plain; charset=utf-8";
                return new ValueTask(context.HttpContext.Response.WriteAsync(
                    "Too many sign-in attempts. Wait a minute, then try again.\n", token));
            };
            options.AddPolicy(LoginLimiter, context => RateLimitPartition.GetFixedWindowLimiter(
                context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
                _ => new FixedWindowRateLimiterOptions { PermitLimit = 10, Window = TimeSpan.FromMinutes(1) }));
        });

        // A cloud host's HTTPS proxy says the page was https, so the cookie is marked Secure.
        // Only the scheme is trusted: X-Forwarded-For is ignored, so nobody can pose as localhost.
        builder.Services.Configure<ForwardedHeadersOptions>(options =>
        {
            options.ForwardedHeaders = ForwardedHeaders.XForwardedProto;
            options.KnownIPNetworks.Clear();
            options.KnownProxies.Clear();
        });
    }

    public static void UseAdminAuth(this WebApplication app)
    {
        var password = app.Configuration["AdminPassword"] ?? "";
        if (password == "")
            app.Logger.LogWarning("No AdminPassword set: the admin page only works from this PC (localhost).");

        app.UseForwardedHeaders();
        app.UseRateLimiter();
        app.UseAuthentication();

        app.Use(async (context, next) =>
        {
            var path = context.Request.Path.Value ?? "";
            var isAdmin = path == "/admin" || path.StartsWith("/admin/", StringComparison.OrdinalIgnoreCase);
            var isAdminSocket = path.Equals("/ws/admin", StringComparison.OrdinalIgnoreCase);
            // The login page and its tab icon are open to everyone.
            var isPublic = path.Equals(LoginPath, StringComparison.OrdinalIgnoreCase)
                || path.Equals("/admin/favicon.png", StringComparison.OrdinalIgnoreCase);
            if ((!isAdmin && !isAdminSocket) || isPublic)
            {
                await next();
                return;
            }
            if (Allowed(context, password))
            {
                // "/admin" -> "/admin/" so its index page is served.
                // (A mapped route would also match "/admin/" and redirect forever.)
                if (path == "/admin") { context.Response.Redirect("/admin/"); return; }
                // Don't let the browser show a stored copy after you sign out.
                if (isAdmin) context.Response.Headers.CacheControl = "no-store";
                await next();
                return;
            }
            if (isAdminSocket) { context.Response.StatusCode = StatusCodes.Status401Unauthorized; return; }
            if (password == "") { await NoPasswordAsync(context); return; }
            context.Response.Redirect(LoginPath);
        });

        app.MapGet(LoginPath, async context =>
        {
            if (Allowed(context, password)) { context.Response.Redirect("/admin/"); return; }
            if (password == "") { await NoPasswordAsync(context); return; }
            context.Response.ContentType = "text/html; charset=utf-8";
            context.Response.Headers.CacheControl = "no-store";
            await context.Response.SendFileAsync(Path.Combine(app.Environment.WebRootPath, "admin", "login.html"));
        });

        app.MapPost(LoginPath, async context =>
        {
            if (password == "") { await NoPasswordAsync(context); return; }
            if (!context.Request.HasFormContentType) { context.Response.StatusCode = StatusCodes.Status400BadRequest; return; }
            var form = await context.Request.ReadFormAsync();
            if (!Matches(form["password"].ToString(), password))
            {
                await Task.Delay(750);  // no quick answers for guessers
                context.Response.Redirect(LoginPath + "?failed=1");
                return;
            }
            var identity = new ClaimsIdentity([new Claim(ClaimTypes.Name, "admin")], CookieAuthenticationDefaults.AuthenticationScheme);
            await context.SignInAsync(new ClaimsPrincipal(identity));
            context.Response.Redirect("/admin/");
        }).RequireRateLimiting(LoginLimiter);

        app.MapPost("/admin/logout", async context =>
        {
            await context.SignOutAsync();
            context.Response.Redirect(LoginPath);
        });
    }

    private static bool Allowed(HttpContext context, string password) =>
        password == ""
            ? context.Connection.RemoteIpAddress is { } ip && IPAddress.IsLoopback(ip)
            : context.User.Identity?.IsAuthenticated == true;

    /// <summary>Compares hashes in constant time, so timing doesn't leak the password.</summary>
    private static bool Matches(string attempt, string password) =>
        CryptographicOperations.FixedTimeEquals(
            SHA256.HashData(Encoding.UTF8.GetBytes(attempt)),
            SHA256.HashData(Encoding.UTF8.GetBytes(password)));

    private static Task NoPasswordAsync(HttpContext context)
    {
        context.Response.StatusCode = StatusCodes.Status403Forbidden;
        context.Response.ContentType = "text/plain; charset=utf-8";
        return context.Response.WriteAsync(
            "The admin page has no password, so it only works on the server's own PC.\n" +
            "Set the AdminPassword setting (environment variable) to sign in from anywhere else.\n");
    }
}
