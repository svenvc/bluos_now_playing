# BluOSNowPlaying

BluOSNowPlaying interfaces with a BluOS (Bluesound) player
to access the necessary data for a 'now playing' status.

![The BluOS Now Playing screen](screenshot.png)

This web application connects to a BluOS player on your network
and offers a page showing a now playing screen.

The HTML page has no interactive UI, it is passive.
The goal is to show this page on any screen that can show a local web page.
There is just one feature: you can toggle play-pause by clicking on the cover art image or on the status label.

A single player on your network will be discovered and used automatically.
If this does not work, you can try setting the environment variable BLUOS_PLAYER_IP to an IPv4 address like 192.168.178.95 to force the use of that player.
Once discovered or set, a config file `.bluos_now_playing.json` with the core connection state will be written in the current directory and used afterwards as long as the player remains reacheable.


## API

At the Elixir level, the configured or discovered player is a well known GenServer called Player.
It has a simple API and broadcasts `{:status_update, <new-status>}` on the `player` PubSub topic.

``` elixir
iex(4)> BluOSNowPlaying.Player.core_state
%{
  "id" => <<144, 86, 130, 183, 31, 236>>,
  "ip" => {192, 168, 178, 95},
  "name" => "NODE NANO",
  "port" => 11000
}

iex(5)> BluOSNowPlaying.Player.status
%{
  state: "stream",
  format: "FLAC 24/44.1",
  image: "https://static.qobuz.com/images/covers/09/31/0075679893109_600.jpg",
  secs: 12,
  totlen: 671,
  player_name: "NODE NANO",
  quality: "HD",
  state_label: "PLAYING",
  title1: "Thinking of a Place",
  title2: "The War On Drugs",
  title3: "A Deeper Understanding"
}

iex(6)> BluOSNowPlaying.Player.status_text
"Thinking of a Place • The War On Drugs • A Deeper Understanding\nHD • FLAC 24/44.1 • NODE NANO • PLAYING\n60/671 • 01:00/11:11 • -10:11 • 8.9%\n"

iex(7)> BluOSNowPlaying.Player.print_status
Thinking of a Place • The War On Drugs • A Deeper Understanding
HD • FLAC 24/44.1 • NODE NANO • PLAYING
60/671 • 01:00/11:11 • -10:11 • 8.9%

:ok

iex(8)> Phoenix.PubSub.subscribe(BluOSNowPlaying.PubSub, "player")
:ok

iex(9)> flush
{:update_status,
 %{
   state: "stream",
   format: "FLAC 24/44.1",
   image: "https://static.qobuz.com/images/covers/09/31/0075679893109_600.jpg",
   secs: 240,
   totlen: 671,
   player_name: "NODE NANO",
   quality: "HD",
   state_label: "PLAYING",
   title1: "Thinking of a Place",
   title2: "The War On Drugs",
   title3: "A Deeper Understanding"
 }}
:ok
```

There is also a small REST API, under http://localhost:4000/api

```bash
$ curl -s http://localhost:4000/api/player-core-state | jq .
{
  "id": "905682B71FEC",
  "ip": "192.168.178.95",
  "name": "NODE NANO",
  "port": 11000
}

$ curl -s http://localhost:4000/api/player-status | jq .    
{
  "state": "play",
  "format": "FLAC 16/44.1",
  "image": "/Artwork?service=Qobuz&songid=Qobuz%3A4619954",
  "secs": 59,
  "totlen": 304,
  "title1": "Love Song",
  "title2": "Simple Minds",
  "title3": "Sons And Fascination/Sister Feelings Call",
  "quality": "CD",
  "player_name": "NODE NANO",
  "state_label": "PLAYING"
}

$ curl http://localhost:4000/api/player-status-text      
Love Song • Simple Minds • Sons And Fascination/Sister Feelings Call
CD • FLAC 16/44.1 • NODE NANO • PLAYING
119/304 • 01:59/05:04 • -03:05 • 39.1%

$ curl -N http://localhost:4000/api/player-status-updates
: heartbeat

data: {"state":"play","format":"FLAC 16/44.1","image":"/Artwork?service=Qobuz&songid=Qobuz%3A4619954","secs":180,"totlen":304,"title1":"Love Song","title2":"Simple Minds","title3":"Sons And Fascination/Sister Feelings Call","quality":"CD","player_name":"NODE NANO","state_label":"PLAYING"}

: heartbeat

data: {"state":"play","format":"FLAC 16/44.1","image":"/Artwork?service=Qobuz&songid=Qobuz%3A4619954","secs":240,"totlen":304,"title1":"Love Song","title2":"Simple Minds","title3":"Sons And Fascination/Sister Feelings Call","quality":"CD","player_name":"NODE NANO","state_label":"PLAYING"}

: heartbeat

data: {"state":"play","format":"FLAC 16/44.1","image":"/Artwork?service=Qobuz&songid=Qobuz%3A4619954","secs":300,"totlen":304,"title1":"Love Song","title2":"Simple Minds","title3":"Sons And Fascination/Sister Feelings Call","quality":"CD","player_name":"NODE NANO","state_label":"PLAYING"}

data: {"state":"play","format":"FLAC 16/44.1","image":"/Artwork?service=Qobuz&songid=Qobuz%3A4673980","secs":0,"totlen":267,"title1":"Promised You A Miracle","title2":"Simple Minds","title3":"New Gold Dream (81/82/83/84)","quality":"CD","player_name":"NODE NANO","state_label":"PLAYING"}

: heartbeat

data: {"state":"play","format":"FLAC 16/44.1","image":"/Artwork?service=Qobuz&songid=Qobuz%3A4673980","secs":59,"totlen":267,"title1":"Promised You A Miracle","title2":"Simple Minds","title3":"New Gold Dream (81/82/83/84)","quality":"CD","player_name":"NODE NANO","state_label":"PLAYING"}

data: {"state":"pause","format":"FLAC 16/44.1","image":"/Artwork?service=Qobuz&songid=Qobuz%3A4673980","secs":88,"totlen":267,"title1":"Promised You A Miracle","title2":"Simple Minds","title3":"New Gold Dream (81/82/83/84)","quality":"CD","player_name":"NODE NANO","state_label":"PAUSED"}
```

The status updates arrive every 60 seconds or faster when a new track starts (the 4th update) or when the state changes (the last update). In between there can be heartbeats. Note that seconds advancing while playing are *not* reported as updates, you will have to do that yourself.


## References

* https://www.bluesound.com
* https://bluos.io
* https://bluesoundprofessional.com
* https://bluesoundprofessional.com/wp-content/uploads/2025/06/BluOS-Custom-Integration-API_v1.7.pdf

The main technical reference is the `BluOS Custom Integration API` version 1.7 which describes
the HTTP REST API to interact with a player as well as the Lenbrook Service Discovery Protocol (LSDP)
to discover players on the network.


## Getting started

This is an Elixir Phoenix project, you'll have to install Elixir, which will depend on Erlang and its BEAM runtime.

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Standalone binaries

The app also builds as a single self-contained executable per platform, with the
Erlang runtime, the release and the assets baked in. Nothing else needs to be
installed on the machine that runs it: get hold of the binary, make it
executable and start it.

```bash
$ chmod +x bluos_now_playing_linux_x86_64
$ ./bluos_now_playing_linux_x86_64
```

The binary starts a server on port 4000 and discovers the player on the local
network exactly like `mix phx.server` does. `PORT`, `PHX_HOST` and
`BLUOS_PLAYER_IP` work as they do for the release, and `SECRET_KEY_BASE` has a
built-in default so no setup is required.

The `maintenance` command covers the things you may want to do without
reinstalling:

```bash
$ ./bluos_now_playing_linux_x86_64 maintenance meta       # what this binary is
$ ./bluos_now_playing_linux_x86_64 maintenance directory  # where it unpacks to
$ ./bluos_now_playing_linux_x86_64 maintenance uninstall  # delete the payload
```

`maintenance meta` reports the app version, the ERTS version of the machine that
built the binary, the Zig target it was built for and the Zig version used, and
answers without unpacking anything. That is the quickest way to confirm you are
running the build you think you are, which matters because a rebuilt binary at
the same version reuses the previously unpacked payload until it is uninstalled.
Like every other invocation, it only works on the platform the binary was built
for.

Binaries are built for macOS (Intel and Apple Silicon), Linux (x86-64 and
arm64) and Windows (x86-64). The macOS binaries are unsigned, so a browser
download has to be cleared with `xattr -d com.apple.quarantine <binary>` before
Gatekeeper will run it. A `curl` install is not affected.

To build them yourself you need Zig **0.16.0** exactly, `xz`, and `7zz` for the
Windows target:

```bash
$ MIX_ENV=prod mix release.burrito        # writes burrito_out/
$ chmod +x burrito_out/*
$ ./test/smoke.sh burrito_out/bluos_now_playing_macos_arm64
```

A binary only runs on the platform it was built for, so run the smoke test
against the one matching your machine. It prints the `host target` it expects,
and prints the binary's app version, ERTS version and target so you can tell
which build you are testing.

The binaries carry a runtime of their own, so nothing has to be installed on the
machine that runs them: not Erlang, not OpenSSL, and on Linux not even a C
library, because the native libraries are linked into the payload rather than
taken from the build machine. That is also why a binary can only run on the
platform it was built for.

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
