extends Node
## Connects the game to the Gemhalla server (tools/run_server.ps1) so the admin page
## can watch this session, set its credits, and force outcomes. When the game isn't
## served by that server, it never connects and the game plays offline as before.
##
## Messages are JSON over a WebSocket at /ws/game:
##   game -> server: hello, state, forced_used, contribute, jackpot_won
##   server -> game: welcome, set_credits, force, reset, message, challenge, jackpots

signal welcomed(credits: int)  # the server's credits for this session
signal credits_set(credits: int)
signal reset_requested(credits: int)
signal message_received(text: String)
signal connection_changed(online: bool)
## The timed challenge changed: {phase, remaining_ms, seconds, standings, credits?, ...}
## (see server/Challenge.cs). Phase "idle" when there is none.
signal challenge_changed(info: Dictionary)
## The linked MAJOR and GRAND meters: {kind: growth in multiples of total bet}.
signal jackpots_changed(meters: Dictionary)

const RECONNECT_SECONDS := 3.0

var session_id := ""
var online := false
## Returns the game's current state ({credits, bet, free_games, ...}) for hello/state.
var state_provider: Callable

var _url := ""
var _socket := WebSocketPeer.new()
var _socket_open := false
var _retry_at_ms := 0
var _forced := ""


func _ready() -> void:
	session_id = _resolve_session_id()
	_url = _server_url()
	if _url.is_empty() or session_id.is_empty():
		# Offline, or waiting for the player's name (see start()).
		set_process(false)
		return
	_connect()


## True when the game is served by the server but no player name was given yet.
func needs_name() -> bool:
	return is_enabled() and session_id.is_empty()


## Starts the session under the player's name (spaces become '-'), writes it into the
## page URL so a reload keeps the same player, and connects. Returns false if the name
## has no usable characters.
func start(player_name: String) -> bool:
	var id := _clean(player_name.strip_edges().replace(" ", "-"))
	if id.is_empty():
		return false
	session_id = id
	if OS.has_feature("web"):
		JavaScriptBridge.eval("history.replaceState(null, '', '?session=' + encodeURIComponent(%s))" % JSON.stringify(id))
	set_process(true)
	_connect()
	return true


func _process(_delta: float) -> void:
	_socket.poll()
	match _socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _socket_open:
				_socket_open = true
				_send({"type": "hello", "session": session_id, "state": _state()})
			while _socket.get_available_packet_count() > 0:
				_handle(_socket.get_packet().get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			if _socket_open or online:
				_socket_open = false
				_set_online(false)
			if Time.get_ticks_msec() >= _retry_at_ms:
				_connect()


## True when this game is served by the Gemhalla server (so it has a session).
func is_enabled() -> bool:
	return not _url.is_empty()


## The outcome the admin forced for the next spin ("" for none). Taking it uses it up.
func take_forced() -> String:
	var force := _forced
	_forced = ""
	if not force.is_empty():
		_send({"type": "forced_used", "outcome": force})
	return force


## Feeds the linked jackpot meters from one paid game.
func contribute_jackpots(amounts: Dictionary) -> void:
	_send({"type": "contribute", "amounts": amounts})


## Tells the server this player won a linked jackpot and was paid `growth` from the meter.
func claim_jackpot(kind: String, growth: float) -> void:
	_send({"type": "jackpot_won", "kind": kind, "growth": growth})


## Tells the server the session's latest state (after a spin or bet change).
func report(extra: Dictionary = {}) -> void:
	var state := _state()
	state.merge(extra, true)
	_send({"type": "state", "state": state})


func _handle(text: String) -> void:
	var msg = JSON.parse_string(text)
	if typeof(msg) != TYPE_DICTIONARY:
		return
	match msg.get("type", ""):
		"welcome":
			_forced = str(msg.get("forced", ""))
			_set_online(true)
			welcomed.emit(int(msg.credits))
			jackpots_changed.emit(msg.get("jackpots", {}))
			# Always say, so a game that missed a challenge's end while offline unlocks.
			var challenge = msg.get("challenge", {"phase": "idle"})
			challenge_changed.emit(challenge if typeof(challenge) == TYPE_DICTIONARY else {"phase": "idle"})
		"challenge":
			challenge_changed.emit(msg)
		"jackpots":
			jackpots_changed.emit(msg.get("meters", {}))
		"set_credits":
			credits_set.emit(int(msg.credits))
		"force":
			_forced = str(msg.get("outcome", ""))
		"reset":
			_forced = ""
			reset_requested.emit(int(msg.credits))
		"message":
			message_received.emit(str(msg.get("text", "")))


func _connect() -> void:
	_retry_at_ms = Time.get_ticks_msec() + int(RECONNECT_SECONDS * 1000)
	_socket = WebSocketPeer.new()
	_socket.connect_to_url(_url)


func _send(msg: Dictionary) -> void:
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.send_text(JSON.stringify(msg))


func _state() -> Dictionary:
	return state_provider.call() if state_provider.is_valid() else {}


func _set_online(value: bool) -> void:
	if online != value:
		online = value
		connection_changed.emit(value)


## Web: the server that served the page, if that is the Gemhalla server; "" on any
## other host (a static web host, for example), where the game plays offline.
## Desktop: --server=ws://host:port/ws/game.
func _server_url() -> String:
	if OS.has_feature("web"):
		var host := str(JavaScriptBridge.eval("location.host"))
		if host.is_empty() or not _served_by_gemhalla_server():
			return ""
		var secure := str(JavaScriptBridge.eval("location.protocol")) == "https:"
		return ("wss://" if secure else "ws://") + host + "/ws/game"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--server="):
			return arg.substr("--server=".length())
	return ""


## Web: asks the page's own host for the server's marker (server/Program.cs maps
## "/gemhalla-server"). Once, at startup; a static host answers 404, so the game stays offline.
func _served_by_gemhalla_server() -> bool:
	var script := "(function(){try{var r=new XMLHttpRequest();" \
		+ "r.open('GET','/gemhalla-server',false);r.send();" \
		+ "return r.status===200&&r.responseText==='gemhalla';}catch(e){return false;}})()"
	return bool(JavaScriptBridge.eval(script))


## Web: ?session=name in the URL, or "" so the game asks for the player's name.
## Desktop: --session=name, else "desktop".
func _resolve_session_id() -> String:
	if OS.has_feature("web"):
		return _clean(str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('session') || ''")))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--session="):
			return _clean(arg.substr("--session=".length()))
	return "desktop"


## Session names: letters, digits, '-' and '_', at most 32 characters.
static func _clean(raw: String) -> String:
	var out := ""
	for ch in raw.strip_edges():
		if ch.is_valid_identifier() or ch.is_valid_int() or ch == "-":
			out += ch
	return out.substr(0, 32)
