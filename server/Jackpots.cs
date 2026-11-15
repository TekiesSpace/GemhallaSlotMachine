using System.Text.Json.Nodes;

namespace GemhallaServer;

/// <summary>
/// The linked MAJOR and GRAND jackpots: one pool for every player. Each meter is its
/// growth above the reset value, in multiples of total bet, as in the game's engine, so
/// a win pays in proportion to the winner's bet and the game's math is the same at every
/// bet level. The games decide wins and pay them, as they do all credits.
///
/// Game socket: contribute {amounts}, jackpot_won {kind, growth}  ->  jackpots {meters}
/// </summary>
public sealed partial class SessionHub
{
    private static readonly string[] LinkedJackpots = ["MAJOR", "GRAND"];
    private const double MaxContribution = 0.05;  // far above a real game's, to stop bad data
    private static readonly TimeSpan JackpotsEvery = TimeSpan.FromSeconds(1);

    private readonly Dictionary<string, double> _jackpots = LinkedJackpots.ToDictionary(kind => kind, _ => 0.0);
    private bool _jackpotsChanged;
    private DateTime _jackpotsSentAt;

    private void ContributeToJackpots(JsonObject? amounts)
    {
        if (amounts is null) return;
        lock (_lock)
        {
            foreach (var kind in LinkedJackpots)
                if (ReadFraction(amounts[kind]) is { } amount)
                {
                    _jackpots[kind] += Math.Min(amount, MaxContribution);
                    _jackpotsChanged = true;
                }
        }
    }

    /// <summary>Takes what the winner was paid out of the pool. Subtracting, rather than
    /// zeroing, keeps anything other players added since the winner's meter last updated.</summary>
    private void TakeJackpot(string? kind, JsonNode? growth)
    {
        if (kind is null || ReadFraction(growth) is not { } paid) return;
        lock (_lock)
        {
            if (!_jackpots.TryGetValue(kind, out var meter)) return;
            _jackpots[kind] = Math.Max(0, meter - paid);
            _jackpotsChanged = true;
        }
    }

    /// <summary>Under _lock: the meters for a game.</summary>
    private JsonObject JackpotMeters()
    {
        var meters = new JsonObject();
        foreach (var (kind, meter) in _jackpots) meters[kind] = meter;
        return meters;
    }

    /// <summary>Sends changed meters to every game, at most once a second.</summary>
    private async Task TickJackpotsAsync()
    {
        var now = DateTime.UtcNow;
        JsonObject msg;
        lock (_lock)
        {
            if (!_jackpotsChanged || now - _jackpotsSentAt < JackpotsEvery) return;
            _jackpotsChanged = false;
            _jackpotsSentAt = now;
            msg = new JsonObject { ["type"] = "jackpots", ["meters"] = JackpotMeters() };
        }
        await SendToAllGamesAsync(msg);
    }

    private void LoadJackpots(Dictionary<string, double>? saved)
    {
        if (saved is null) return;
        foreach (var kind in LinkedJackpots)
            if (saved.TryGetValue(kind, out var meter) && double.IsFinite(meter)) _jackpots[kind] = Math.Max(0, meter);
    }

    private static double? ReadFraction(JsonNode? node) =>
        node is JsonValue value && value.TryGetValue<double>(out var number) && double.IsFinite(number) && number >= 0 ? number : null;
}
