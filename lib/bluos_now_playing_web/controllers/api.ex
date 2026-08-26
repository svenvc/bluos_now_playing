defmodule BluOSNowPlayingWeb.API do
  use BluOSNowPlayingWeb, :controller

  alias BluOSNowPlaying.Player
  alias BluOSNowPlaying.Utils

  def player_status(conn, _params) do
    json(conn, Player.status())
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
