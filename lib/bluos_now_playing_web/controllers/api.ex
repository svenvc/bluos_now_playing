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
      uri: "/api/player-status-updates",
      description: "an SSE stream of updates of the status of the BluOS player"
    },
    %{
      uri: "/api/player-status-text",
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

  def player_status_text(conn, params) do
    refresh? = Map.get(params, "refresh", "false") == "true"

    text(conn, Player.status_text(refresh?))
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

  def player_status_updates(conn, _params) do
    Phoenix.PubSub.subscribe(BluOSNowPlaying.PubSub, "player")

    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("x-accel-buffering", "no")
      |> send_chunked(200)

    loop(conn)
  end

  @heartbeat_ms 37_000

  defp loop(conn) do
    receive do
      {:update_status, player_status} ->
        case chunk(conn, "data: #{JSON.encode!(player_status)}\n\n") do
          {:ok, conn} ->
            loop(conn)

          {:error, :closed} ->
            conn
        end
    after
      @heartbeat_ms ->
        case chunk(conn, ": heartbeat\n\n") do
          {:ok, conn} ->
            loop(conn)

          {:error, :closed} ->
            conn
        end
    end
  end
end
