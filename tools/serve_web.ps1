# Serves build/web at http://localhost:8060 so the browser build can be played locally.
# (Opening index.html directly from disk doesn't work; browsers block it.)
param([int]$Port = 8060)

$root = Join-Path (Split-Path -Parent $PSScriptRoot) "build\web"
$types = @{
    ".html" = "text/html"; ".js" = "application/javascript"; ".wasm" = "application/wasm"
    ".pck" = "application/octet-stream"; ".png" = "image/png"; ".ico" = "image/x-icon"
    ".svg" = "image/svg+xml"; ".json" = "application/json"
}
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "Serving $root at http://localhost:$Port (Ctrl+C to stop)"
try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $path = [Uri]::UnescapeDataString($context.Request.Url.AbsolutePath.TrimStart("/"))
        if ($path -eq "") { $path = "index.html" }
        $file = Join-Path $root $path
        $response = $context.Response
        # Only serve files inside build/web.
        $full = [IO.Path]::GetFullPath($file)
        if ($full.StartsWith([IO.Path]::GetFullPath($root)) -and (Test-Path $full -PathType Leaf)) {
            $ext = [IO.Path]::GetExtension($full).ToLower()
            $response.ContentType = if ($types.ContainsKey($ext)) { $types[$ext] } else { "application/octet-stream" }
            $bytes = [IO.File]::ReadAllBytes($full)
            $response.ContentLength64 = $bytes.Length
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
        } else {
            $response.StatusCode = 404
        }
        $response.Close()
    }
} finally {
    $listener.Stop()
}
