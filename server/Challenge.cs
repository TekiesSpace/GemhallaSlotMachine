using System.Text.Json.Nodes;

namespace GemhallaServer;

/// <summary>
/// The timed challenge: the admin starts it, every game online counts down together, then
/// everyone plays from the house default for the set time; whoever has the most money
/// when it ends wins. Afterwards everyone is put back on the house default.
///
/// Phases: idle -> countdown (play locked) -> running -> ended (play locked while the
/// last spins finish) -> results (announced, everyone reset) -> idle.
///
/// Game socket:  state carries "busy" (a spin is in progress)
///               -> challenge {phase, remaining_ms, seconds, standings, credits?, winners?}
/// Admin socket: challenge_start {seconds, lead_seconds}, challenge_cancel
/// </summary>
public sealed partial class SessionHub
{
    private const int SettleSeconds = 30;  // the longest "ended" waits for spins to finish
    private const int MaxStandings = 50;
    private static readonly TimeSpan StandingsEvery = TimeSpan.FromSeconds(1);

    private enum Phase { Idle, Countdown, Running, Ended }

    private Phase _phase = Phase.Idle;
    private DateTime _phaseEndsAt;  // countdown: the start; running: the end; ended: settle deadline
    private int _challengeSeconds;
    private readonly HashSet<string> _participants = new(StringComparer.OrdinalIgnoreCase);
    private bool _standingsChanged;
    private DateTime _standingsSentAt;
    private JsonObject? _lastResults;

    /// <summary>Moves the challenge along and sends the jackpot meters: started with the
    /// hub, checks four times a second.</summary>
    private async Task RunClockAsync()
    {
        using var timer = new PeriodicTimer(TimeSpan.FromMilliseconds(250));
        while (await timer.WaitForNextTickAsync())
        {
            try
            {
                await TickChallengeAsync();
                await TickJackpotsAsync();
            }
            catch (Exception ex) { _log.LogError(ex, "Clock failed"); }
        }
    }

    private async Task TickChallengeAsync()
    {
        var now = DateTime.UtcNow;
        JsonObject? toGames = null;
        lock (_lock)
        {
            switch (_phase)
            {
                case Phase.Countdown when now >= _phaseEndsAt:
                    // Go: everyone online plays, from the house default.
                    _phase = Phase.Running;
                    _phaseEndsAt = now.AddSeconds(_challengeSeconds);
                    _participants.Clear();
                    foreach (var id in _games.Keys)
                    {
                        _participants.Add(id);
                        ResetToDefault(_sessions[id]);
                    }
                    toGames = ChallengeMessage(credits: _defaultCredits);
                    _log.LogInformation("Challenge started with {Count} players", _participants.Count);
                    break;
                case Phase.Running when now >= _phaseEndsAt:
                    _phase = Phase.Ended;
                    _phaseEndsAt = now.AddSeconds(SettleSeconds);
                    toGames = ChallengeMessage();
                    break;
                case Phase.Running when _standingsChanged && now - _standingsSentAt >= StandingsEvery:
                    _standingsChanged = false;
                    _standingsSentAt = now;
                    toGames = ChallengeMessage();
                    break;
                case Phase.Ended when now >= _phaseEndsAt || !AnyParticipantSpinning():
                    toGames = AnnounceResults();
                    break;
            }
        }
        if (toGames is null) return;
        await SendToAllGamesAsync(toGames);
        SaveAndBroadcast();
    }

    /// <summary>Starts the countdown; returns an error message, or null.</summary>
    private string? StartChallenge(JsonObject msg)
    {
        var seconds = ReadAmount(msg["seconds"]);
        var lead = ReadAmount(msg["lead_seconds"]) ?? 10;
        if (seconds is null or < 10 or > 7200) return "A challenge lasts from 10 seconds to 2 hours.";
        if (lead is < 3 or > 300) return "The countdown lasts from 3 seconds to 5 minutes.";
        JsonObject toGames;
        lock (_lock)
        {
            if (_phase != Phase.Idle) return "A challenge is already on. Cancel it first.";
            if (_games.Count == 0) return "Nobody is online to challenge.";
            _phase = Phase.Countdown;
            _challengeSeconds = (int)seconds.Value;
            _phaseEndsAt = DateTime.UtcNow.AddSeconds(lead);
            _participants.Clear();
            toGames = ChallengeMessage();
        }
        _log.LogInformation("Challenge of {Seconds}s starts in {Lead}s", seconds, lead);
        _ = SendToAllGamesAsync(toGames);
        return null;
    }

    /// <summary>Stops the challenge with no winner; everyone in it goes back to the house default.</summary>
    private string? CancelChallenge()
    {
        JsonObject toGames;
        lock (_lock)
        {
            if (_phase == Phase.Idle) return "There is no challenge to cancel.";
            var resetAll = _phase != Phase.Countdown;
            foreach (var id in _participants)
                if (_sessions.TryGetValue(id, out var s)) ResetToDefault(s);
            _phase = Phase.Idle;
            _participants.Clear();
            toGames = ChallengeMessage(credits: resetAll ? _defaultCredits : null);
            toGames["cancelled"] = true;
        }
        _ = SendToAllGamesAsync(toGames);
        return null;
    }

    /// <summary>Under _lock: ranks everyone, puts them back on the house default, returns the
    /// results message for the games, and goes idle.</summary>
    private JsonObject AnnounceResults()
    {
        var standings = Standings(int.MaxValue);
        var best = standings.Count > 0 ? standings[0].Credits : 0;
        var winners = new JsonArray([.. standings.Where(s => s.Credits == best).Select(s => (JsonNode)s.Id)]);
        var results = new JsonObject
        {
            ["type"] = "challenge",
            ["phase"] = "results",
            ["seconds"] = _challengeSeconds,
            ["winners"] = winners,
            ["winning_credits"] = best,
            ["standings"] = StandingsJson(standings, MaxStandings),
            ["credits"] = _defaultCredits,
        };
        foreach (var id in _participants)
            if (_sessions.TryGetValue(id, out var s)) ResetToDefault(s);
        _lastResults = results.DeepClone().AsObject();
        _lastResults["finishedAt"] = DateTime.UtcNow.ToString("o");
        _log.LogInformation("Challenge won by {Winners} with {Credits}", string.Join(", ", winners), best);
        _phase = Phase.Idle;
        _participants.Clear();
        return results;
    }

    /// <summary>Under _lock: a game said hello. During a challenge it joins in; returns the
    /// challenge message for its welcome (null when there's no challenge).</summary>
    private JsonObject? JoinChallenge(Session session)
    {
        if (_phase == Phase.Idle) return null;
        if (_phase == Phase.Running && _participants.Add(session.Id))
        {
            // Late, but still in: from the house default like everyone else.
            ResetToDefault(session);
            _standingsChanged = true;
        }
        return ChallengeMessage();
    }

    /// <summary>Under _lock: a participant's credits changed.</summary>
    private void NoteChallengeCredits(string id)
    {
        if (_phase == Phase.Running && _participants.Contains(id)) _standingsChanged = true;
    }

    private bool AnyParticipantSpinning() =>
        _participants.Any(id => _games.ContainsKey(id) && _sessions.TryGetValue(id, out var s) && s.Busy);

    private void ResetToDefault(Session session)
    {
        session.Credits = _defaultCredits;
        session.FreeGames = 0;
    }

    /// <summary>Under _lock: the challenge as the games see it.</summary>
    private JsonObject ChallengeMessage(long? credits = null)
    {
        var msg = new JsonObject
        {
            ["type"] = "challenge",
            ["phase"] = _phase.ToString().ToLowerInvariant(),
            ["remaining_ms"] = _phase == Phase.Idle ? 0 : Math.Max(0, (long)(_phaseEndsAt - DateTime.UtcNow).TotalMilliseconds),
            ["seconds"] = _challengeSeconds,
            ["start_credits"] = _defaultCredits,
            ["standings"] = StandingsJson(Standings(MaxStandings), MaxStandings),
        };
        if (credits is not null) msg["credits"] = credits.Value;
        return msg;
    }

    /// <summary>Under _lock: the challenge for the admin page.</summary>
    private JsonObject ChallengeSnapshot()
    {
        var snapshot = ChallengeMessage();
        snapshot.Remove("type");
        snapshot["players"] = _participants.Count;
        if (_lastResults is not null) snapshot["lastResults"] = _lastResults.DeepClone();
        return snapshot;
    }

    private List<Session> Standings(int max) =>
        [.. _participants.Select(id => _sessions.GetValueOrDefault(id)).OfType<Session>()
            .OrderByDescending(s => s.Credits).ThenBy(s => s.Id, StringComparer.OrdinalIgnoreCase).Take(max)];

    private JsonArray StandingsJson(List<Session> standings, int max) =>
        new([.. standings.Take(max).Select(s => (JsonNode)new JsonObject
        {
            ["id"] = s.Id, ["credits"] = s.Credits, ["online"] = _games.ContainsKey(s.Id),
        })]);

    private async Task SendToAllGamesAsync(JsonObject msg)
    {
        List<Client> targets;
        lock (_lock) targets = [.. _games.Values.SelectMany(list => list)];
        foreach (var client in targets) await client.SendAsync(msg);
    }
}
