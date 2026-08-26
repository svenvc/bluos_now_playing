defmodule BluOSNowPlayingWeb.API do
  use BluOSNowPlayingWeb, :controller

  alias BluOSNowPlaying.Player
  alias BluOSNowPlaying.Utils

  @root [
    %{
      uri: "/api/player-core-state",
      description: "the core connection details of the BluOS player"
    },
    %{
      uri: "/api/player-status",
      description: "the status of the BluOS player, add refresh=true for up to date info"
    },
    %{
      uri: "/api/player-toggle-play-pause",
      description: "action to toggle the player play-pause state"
    }
  ]
  def root(conn, _params) do
    json(conn, @root)
  end

  def player_status(conn, params) do
    refresh? = Map.get(params, "refresh", "false") == "true"

    json(conn, Player.status(refresh?))
  end

  def player_core_state(conn, _params) do
    json(
      conn,
      Player.core_state()
      |> Map.update("ip", nil, &Utils.ip_to_string/1)
      |> Map.update("id", nil, &Base.encode16/1)
    )
  end

  def player_toggle_play_pause(conn, _params) do
    json(conn, Player.toggle_play_pause())
  end
end
