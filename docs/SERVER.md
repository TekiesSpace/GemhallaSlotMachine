# The Gemhalla server

The server (`server/`, ASP.NET Core on .NET 10) hosts the browser build of the game and the admin page, and connects them with WebSockets. With it, several players can play at once, each in their own named session, sharing the MAJOR and GRAND jackpots, and an admin can watch and steer every session live.

Without it, the game plays offline: the desktop game always, and the browser game whenever a host other than this server serves it. At startup the browser game asks its own host for `/gemhalla-server`; only this server answers, so only then does the game connect.

## Running it

Export the browser game to `build/web` first (see the README), then:

```bash
dotnet run --project server
```

| Address | What it is |
| --- | --- |
| `http://localhost:8070/?session=alice` | The game, as player "alice". Each name is its own player with its own credits. Without a name, the game asks for one and puts it in the address, so a reload keeps the same player |
| `http://localhost:8070/admin` | The admin page |
| `/ws/game`, `/ws/admin` | The WebSockets behind them (JSON messages) |

The desktop game can connect too: `godot --path . -- --server=ws://localhost:8070/ws/game --session=alice`.

## Settings

All settings come from environment variables (or any other ASP.NET Core configuration source):

| Setting | Default | What it does |
| --- | --- | --- |
| `Url` | `http://localhost:8070` | Where the server listens. The container image sets `http://+:8080` |
| `GameDir` | `../build/web` (from `server/`) | The browser build to serve |
| `DataDir` | `server/data` | Where sessions, the linked jackpots and the sign-in keys are saved |
| `AdminPassword` | none | Password for the admin page (below) |

## Sessions

The server is the authority for each session's credits. Sessions are saved to `sessions.json` in the data folder, so they survive restarts. Run a single copy of the server: sessions are one file, so several copies would each keep their own.

## The admin page

The admin page shows every session live: online or not, credits, bet, last win and spins. From it you can:

- set the starting credits for new sessions, and set up named sessions with their own starting credits;
- set or add credits for a session;
- force the next spin: a big line win, free games, Hold & Spin, or a MINI, MINOR, MAJOR or GRAND jackpot;
- send a player a message;
- reset or delete a session;
- start and cancel a timed challenge.

Forced spins pick real reel positions that produce the outcome, so they look and pay like natural ones. `tools/test_forced_outcomes.gd` checks every one.

## Admin password

Anyone who can open the admin page can change credits and force wins, so it's guarded:

- **With `AdminPassword` set**, `/admin` asks for the password and signs you in for 12 hours, renewed while you use it. **Sign out** is in the header.
- **Without it**, the admin page only answers requests from the same machine (localhost); anything else gets "403 Forbidden". The game itself is never guarded.
- The sign-in cookie is HttpOnly and SameSite=Strict, and marked Secure over HTTPS. Ten wrong passwords in a minute from one address get "too many attempts".
- The cookie's signing keys are saved in the data folder (`keys/`), so a restart doesn't sign you out. The log's "No XML encryptor configured" warning refers to them and is expected.

Keep the password out of source control: pass it as an environment variable or your host's secret store. `compose.yaml` reads it from a git-ignored `.env` file.

## Linked jackpots

On the server, MAJOR and GRAND are linked: every player's paid bets feed the same two meters, and anyone can win them (`server/Jackpots.cs`, saved with the sessions). Meters are kept in multiples of total bet, so everyone sees the same growth scaled to their own bet, and the return is the same at every bet level. Offline, each save keeps its own meters.

## Timed challenge

A race for everyone online, started from the admin page's **Timed challenge** card (length in minutes, default 10, and a countdown, default 10 seconds). Run by `server/Challenge.cs` and shown in the game by `scripts/ui/challenge_view.gd`.

1. **Countdown:** every game online shows "SLOT CHALLENGE, starts in 0:10" with the rules, and play is locked.
2. **Running:** everyone online is set to the starting credit (the house default, $1,000) with no free games, and plays. A banner shows the time left (red in the last 30 seconds), your place and the leader. There are no refills while it runs, and players who join meanwhile start from the starting credit too.
3. **Time's up:** play locks. Spins already under way, Hold & Spin included, finish and count; the results wait for them, up to 30 seconds.
4. **Results:** everyone sees the winner (ties share it, with fireworks), their own place and the top five. Everyone goes back to the starting credit and can play on.

**Cancel challenge** stops it with no winner and puts everyone back on the starting credit. A challenge in progress doesn't survive a server restart; the games just unlock.

## In a container

The `Dockerfile` builds the server in a .NET SDK stage and runs it on the smaller ASP.NET runtime as a non-root user, listening on port 8080, with the browser build in `/app/game` and data in the `/data` volume. Godot isn't in the image, so export the browser game before `docker build`. See the README for `docker build` and `docker run`.

To put it on the internet:

- serve it over HTTPS (a reverse proxy or your host's ingress); the game and admin page switch to `wss://` by themselves when the page is HTTPS;
- set `AdminPassword` as a secret;
- mount persistent storage at `/data`, or sessions start empty after every restart;
- run exactly one copy.

## Desktop shortcuts (Windows)

A link dragged from the browser to the desktop shows the browser's icon. For Gemhalla's own icons (the Rune Gem for the game, a sapphire for the admin page):

```powershell
.\tools\make_shortcuts.ps1                                 # "Gemhalla" (asks for a name) + "Gemhalla Admin"
.\tools\make_shortcuts.ps1 -Session alice                  # "Gemhalla - alice", straight into that session
.\tools\make_shortcuts.ps1 -Session alice -Url https://gemhalla.example.com
```

`-Name` names (and replaces) the game shortcut; `-NoAdmin` skips the admin one. The icons are copied to `%LOCALAPPDATA%\Gemhalla\icons`, so the shortcuts keep them if the project folder moves.
