using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace GemhallaServer;

/// <summary>
/// Holds every game session, relays admin commands to the games, and keeps the admin
/// pages up to date. Sessions (and the default starting credits) are saved to
/// data/sessions.json so they survive a server restart.
///
/// Game socket  (/ws/game):  hello, state, forced_used  ->  welcome, set_credits, force, reset, message, challenge
/// Admin socket (/ws/admin): actions (see HandleAdminAsync)  ->  snapshot of all sessions
/// The timed challenge is in Challenge.cs, the linked jackpots in Jackpots.cs.
/// </summary>
public sealed partial class SessionHub
{
    public static readonly string[] ForcedOutcomes =
    [
        "line_win", "free_games", "hold_spin",
        "jackpot_mini", "jackpot_minor", "jackpot_major", "jackpot_grand",
    ];

    private const int MaxMessageBytes = 64 * 1024;
    private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase, WriteIndented = true };

    private readonly object _lock = new();
    private readonly object _saveLock = new();  // one file write at a time
    private readonly string _dataPath;
    private readonly ILogger<SessionHub> _log;
    private readonly Dictionary<string, Session> _sessions = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, List<Client>> _games = new(StringComparer.OrdinalIgnoreCase);
    private readonly List<Client> _admins = [];
    private long _defaultCredits = 100_000;  // cents: new sessions start with $1,000

    public SessionHub(IWebHostEnvironment env, IConfiguration config, ILogger<SessionHub> log)
    {
        _log = log;
        _dataPath = Path.Combine(ResolveDataDir(env, config), "sessions.json");
        Load();
        _ = RunClockAsync();
    }

    /// <summary>Where sessions (and the admin sign-in keys) are saved. DataDir lets a
    /// container keep them on a mounted volume.</summary>
    public static string ResolveDataDir(IWebHostEnvironment env, IConfiguration config) =>
        Path.GetFullPath(Path.Combine(env.ContentRootPath, config["DataDir"] ?? "data"));

    // --- Game connections ---------------------------------------------------------

    public async Task RunGameAsync(WebSocket socket, CancellationToken cancel)
    {
        var client = new Client(socket);
        string? sessionId = null;
        try
        {
            await foreach (var msg in ReceiveAsync(socket, cancel))
            {
                switch ((string?)msg["type"])
                {
                    case "hello":
                        sessionId = CleanId((string?)msg["session"]);
                        if (sessionId.Length == 0) return;
                        await HandleHelloAsync(sessionId, client, msg["state"] as JsonObject);
                        break;
                    case "state" when sessionId is not null:
                        UpdateFromGame(sessionId, msg["state"] as JsonObject);
                        break;
                    case "contribute" when sessionId is not null:
                        ContributeToJackpots(msg["amounts"] as JsonObject);
                        break;
                    case "jackpot_won" when sessionId is not null:
                        TakeJackpot((string?)msg["kind"], msg["growth"]);
                        break;
                    case "forced_used" when sessionId is not null:
                        lock (_lock) { if (_sessions.TryGetValue(sessionId, out var s)) s.Forced = ""; }
                        SaveAndBroadcast();
                        break;
                }
            }
        }
        finally
        {
            if (sessionId is not null)
            {
                lock (_lock)
                {
                    if (_games.TryGetValue(sessionId, out var list))
                    {
                        list.Remove(client);
                        if (list.Count == 0)
                        {
                            _games.Remove(sessionId);
                            // Gone mid-spin: don't keep a finished challenge waiting for it.
                            if (_sessions.TryGetValue(sessionId, out var s)) s.Busy = false;
                        }
                    }
                }
                SaveAndBroadcast();
            }
        }
    }

    private async Task HandleHelloAsync(string id, Client client, JsonObject? state)
    {
        Session session;
        JsonObject welcome;
        lock (_lock)
        {
            // The server is the authority for a known session's credits; a new session
            // starts with the default amount set on the admin page.
            if (!_sessions.TryGetValue(id, out session!))
            {
                session = new Session { Id = id, Credits = _defaultCredits };
                _sessions[id] = session;
            }
            ApplyState(session, state, includeCredits: false);
            if (!_games.TryGetValue(id, out var list)) _games[id] = list = [];
            list.Add(client);
            // A challenge in progress takes them in (and may set their credits), so it goes first.
            var challenge = JoinChallenge(session);
            welcome = new JsonObject
            {
                ["type"] = "welcome", ["credits"] = session.Credits, ["forced"] = session.Forced, ["jackpots"] = JackpotMeters(),
            };
            if (challenge is not null) welcome["challenge"] = challenge;
        }
        await client.SendAsync(welcome);
        _log.LogInformation("Session {Id} connected", id);
        SaveAndBroadcast();
    }

    private void UpdateFromGame(string id, JsonObject? state)
    {
        lock (_lock)
        {
            if (_sessions.TryGetValue(id, out var session))
            {
                ApplyState(session, state, includeCredits: true);
                NoteChallengeCredits(id);
            }
        }
        SaveAndBroadcast();
    }

    private static void ApplyState(Session session, JsonObject? state, bool includeCredits)
    {
        session.LastSeen = DateTime.UtcNow;
        if (state is null) return;
        if (includeCredits && state["credits"] is JsonValue c) session.Credits = Math.Max(0, (long)c.GetValue<double>());
        if (state["busy"] is JsonValue busy && busy.TryGetValue<bool>(out var spinning)) session.Busy = spinning;
        if (state["bet"] is JsonValue b) session.Bet = (int)b.GetValue<double>();
        if (state["free_games"] is JsonValue f) session.FreeGames = (int)f.GetValue<double>();
        if (state["last_win"] is JsonValue w) session.LastWin = (long)w.GetValue<double>();
        if (state["spins"] is JsonValue n) session.Spins = (int)n.GetValue<double>();
    }

    // --- Admin connections --------------------------------------------------------

    public async Task RunAdminAsync(WebSocket socket, CancellationToken cancel)
    {
        var client = new Client(socket);
        lock (_lock) _admins.Add(client);
        try
        {
            await client.SendAsync(Snapshot());
            await foreach (var msg in ReceiveAsync(socket, cancel))
            {
                var error = await HandleAdminAsync(msg);
                if (error is not null) await client.SendAsync(new JsonObject { ["type"] = "error", ["text"] = error });
                SaveAndBroadcast();
            }
        }
        finally
        {
            lock (_lock) _admins.Remove(client);
        }
    }

    /// <summary>Applies one admin action; returns an error message, or null on success.</summary>
    private async Task<string?> HandleAdminAsync(JsonObject msg)
    {
        var action = (string?)msg["action"];
        if (action == "set_default")
        {
            var amount = ReadAmount(msg["credits"]);
            if (amount is null) return "Enter a starting amount of 0 or more.";
            lock (_lock) _defaultCredits = amount.Value;
            return null;
        }
        if (action == "challenge_start") return StartChallenge(msg);
        if (action == "challenge_cancel") return CancelChallenge();

        var id = CleanId((string?)msg["session"]);
        if (id.Length == 0) return "Session names use letters, digits, '-' and '_'.";
        Session? session;
        lock (_lock) _sessions.TryGetValue(id, out session);

        switch (action)
        {
            case "create":
            {
                var amount = ReadAmount(msg["credits"]) ?? _defaultCredits;
                lock (_lock)
                {
                    session ??= _sessions[id] = new Session { Id = id, LastSeen = DateTime.UtcNow };
                    session.Credits = amount;
                }
                await SendToGameAsync(id, new JsonObject { ["type"] = "set_credits", ["credits"] = amount });
                return null;
            }
            case "set_credits":
            case "add_credits":
            {
                if (session is null) return $"No session named {id}.";
                var amount = action == "set_credits" ? ReadAmount(msg["credits"]) : ReadSigned(msg["amount"]);
                if (amount is null) return "Enter a whole number of credits.";
                long credits;
                lock (_lock)
                {
                    credits = session.Credits = Math.Max(0, action == "set_credits" ? amount.Value : session.Credits + amount.Value);
                    NoteChallengeCredits(id);
                }
                await SendToGameAsync(id, new JsonObject { ["type"] = "set_credits", ["credits"] = credits });
                return null;
            }
            case "force":
            {
                if (session is null) return $"No session named {id}.";
                var outcome = (string?)msg["outcome"] ?? "";
                if (outcome.Length > 0 && !ForcedOutcomes.Contains(outcome)) return $"Unknown outcome {outcome}.";
                lock (_lock) session.Forced = outcome;
                await SendToGameAsync(id, new JsonObject { ["type"] = "force", ["outcome"] = outcome });
                return null;
            }
            case "reset":
            {
                if (session is null) return $"No session named {id}.";
                long credits;
                lock (_lock)
                {
                    credits = session.Credits = _defaultCredits;
                    session.FreeGames = 0;
                    session.Forced = "";
                }
                await SendToGameAsync(id, new JsonObject { ["type"] = "reset", ["credits"] = credits });
                return null;
            }
            case "message":
            {
                var text = ((string?)msg["text"] ?? "").Trim();
                if (text.Length == 0) return "Type a message first.";
                if (text.Length > 120) text = text[..120];
                await SendToGameAsync(id, new JsonObject { ["type"] = "message", ["text"] = text });
                return null;
            }
            case "delete":
                lock (_lock) _sessions.Remove(id);
                return null;
            default:
                return $"Unknown action {action}.";
        }
    }

    // --- Messaging ----------------------------------------------------------------

    private async Task SendToGameAsync(string id, JsonObject msg)
    {
        List<Client> targets;
        lock (_lock) targets = _games.TryGetValue(id, out var list) ? [.. list] : [];
        foreach (var client in targets) await client.SendAsync(msg);
    }

    private void SaveAndBroadcast()
    {
        Save();
        var snapshot = Snapshot();
        List<Client> admins;
        lock (_lock) admins = [.. _admins];
        foreach (var admin in admins) _ = admin.SendAsync(snapshot);
    }

    private JsonObject Snapshot()
    {
        lock (_lock)
        {
            var list = new JsonArray();
            foreach (var s in _sessions.Values.OrderBy(s => s.Id, StringComparer.OrdinalIgnoreCase))
            {
                list.Add(new JsonObject
                {
                    ["id"] = s.Id,
                    ["online"] = _games.ContainsKey(s.Id),
                    ["credits"] = s.Credits,
                    ["bet"] = s.Bet,
                    ["freeGames"] = s.FreeGames,
                    ["lastWin"] = s.LastWin,
                    ["spins"] = s.Spins,
                    ["forced"] = s.Forced,
                    ["lastSeen"] = s.LastSeen.ToString("o"),
                });
            }
            return new JsonObject
            {
                ["type"] = "snapshot",
                ["defaultCredits"] = _defaultCredits,
                ["outcomes"] = new JsonArray([.. ForcedOutcomes.Select(o => (JsonNode)o)]),
                ["sessions"] = list,
                ["challenge"] = ChallengeSnapshot(),
            };
        }
    }

    private static async IAsyncEnumerable<JsonObject> ReceiveAsync(WebSocket socket,
        [System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken cancel)
    {
        var buffer = new byte[8 * 1024];
        using var message = new MemoryStream();
        while (socket.State == WebSocketState.Open)
        {
            WebSocketReceiveResult result;
            try { result = await socket.ReceiveAsync(buffer, cancel); }
            catch (Exception ex) when (ex is WebSocketException or OperationCanceledException) { yield break; }
            if (result.MessageType == WebSocketMessageType.Close) yield break;
            message.Write(buffer, 0, result.Count);
            if (message.Length > MaxMessageBytes) yield break;
            if (!result.EndOfMessage) continue;
            JsonObject? obj = null;
            try { obj = JsonNode.Parse(Encoding.UTF8.GetString(message.ToArray())) as JsonObject; }
            catch (JsonException) { }
            message.SetLength(0);
            if (obj is not null) yield return obj;
        }
    }

    // --- Helpers --------------------------------------------------------------------

    /// <summary>Session names: letters, digits, '-' and '_', at most 32 characters (matches the game).</summary>
    public static string CleanId(string? raw)
    {
        var id = new string((raw ?? "").Trim().Where(ch => char.IsAsciiLetterOrDigit(ch) || ch is '-' or '_').ToArray());
        return id.Length > 32 ? id[..32] : id;
    }

    private static long? ReadAmount(JsonNode? node)
    {
        var value = ReadSigned(node);
        return value is >= 0 ? value : null;
    }

    private static long? ReadSigned(JsonNode? node)
    {
        try
        {
            return node switch
            {
                JsonValue v when v.TryGetValue<double>(out var d) && double.IsFinite(d) => (long)Math.Round(d),
                JsonValue v when v.TryGetValue<string>(out var s) && long.TryParse(s.Replace(",", ""), out var l) => l,
                _ => null,
            };
        }
        catch (FormatException) { return null; }
    }

    private void Load()
    {
        if (!File.Exists(_dataPath)) return;
        try
        {
            var data = JsonSerializer.Deserialize<SavedData>(File.ReadAllText(_dataPath), JsonOptions);
            if (data is null) return;
            _defaultCredits = Math.Max(0, data.DefaultCredits);
            foreach (var s in data.Sessions) _sessions[s.Id] = s;
            LoadJackpots(data.Jackpots);
        }
        catch (Exception ex)
        {
            _log.LogWarning(ex, "Could not read {Path}; starting with no sessions", _dataPath);
        }
    }

    private void Save()
    {
        string json;
        lock (_lock) json = JsonSerializer.Serialize(new SavedData(_defaultCredits, [.. _sessions.Values], _jackpots), JsonOptions);
        // Saves come from several connections at once; they must not share the temp file.
        lock (_saveLock)
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(_dataPath)!);
                var temp = _dataPath + ".tmp";
                File.WriteAllText(temp, json);
                File.Move(temp, _dataPath, overwrite: true);
            }
            catch (IOException ex)
            {
                _log.LogWarning(ex, "Could not save sessions");
            }
        }
    }

    private sealed record SavedData(long DefaultCredits, List<Session> Sessions, Dictionary<string, double>? Jackpots = null);

    public sealed class Session
    {
        public string Id { get; set; } = "";
        public long Credits { get; set; }
        public int Bet { get; set; }
        public int FreeGames { get; set; }
        public long LastWin { get; set; }
        public int Spins { get; set; }
        public string Forced { get; set; } = "";
        public DateTime LastSeen { get; set; }
        /// <summary>A spin is in progress (the game says so); not saved.</summary>
        [System.Text.Json.Serialization.JsonIgnore]
        public bool Busy { get; set; }
    }

    /// <summary>A socket plus a gate, since a WebSocket allows only one send at a time.</summary>
    private sealed class Client(WebSocket socket)
    {
        private readonly SemaphoreSlim _gate = new(1, 1);

        public async Task SendAsync(JsonObject msg)
        {
            var bytes = Encoding.UTF8.GetBytes(msg.ToJsonString());
            await _gate.WaitAsync();
            try
            {
                if (socket.State == WebSocketState.Open)
                    await socket.SendAsync(bytes, WebSocketMessageType.Text, true, CancellationToken.None);
            }
            catch (WebSocketException) { }
            finally { _gate.Release(); }
        }
    }
}
