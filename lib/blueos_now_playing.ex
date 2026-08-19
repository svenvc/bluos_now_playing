defmodule BlueOSNowPlaying do

  alias BlueOSNowPlaying.API
  alias BlueOSNowPlaying.Utils

  @moduledoc """
  BlueOSNowPlaying is an interface to a BlueOS (Bluesound) player
  to access the necessary data for a 'now playing' status.
  """

  @filename ".bluos_now_playing.json"
  @state_keys ~w(id name ip port)s

  def save_state(state) when is_map(state) do
    state
    |> Map.take(@state_keys)
    |> Map.update("ip", nil, &Utils.ip_to_string/1)
    |> Map.update("id", nil, &Base.encode16/1)
    |> JSON.encode_to_iodata!()
    |> then(fn data ->
      File.write(@filename, data)
    end)
  end

  def load_state() do
    if File.exists?(@filename) do
      File.read!(@filename)
      |> JSON.decode!()
      |> Map.update("ip", nil, &Utils.string_to_ip/1)
      |> Map.update("id", nil, &Base.decode16!/1)
    else
      %{"id" => nil, "name" => nil, "ip" => nil, "port" => API.default_port()}
    end
  end

  def is_player_up?(state) when is_map(state) do
    sync_state = API.get_sync_status(state["ip"], state["port"])
    state["name"] == sync_state["name"]
  end

  @main_status_attributes ~w(title1 title2 title3 state totlen secs image quality streamFormat)s
  @integer_attributes ~w(secs totlen)s

  def process_status(map) do
    map = Map.take(map, @main_status_attributes)

    Enum.reduce(@integer_attributes, map, fn key, acc ->
      if Map.has_key?(map, key) do
        Map.update!(acc, key, &String.to_integer/1)
      else
        acc
      end
    end)
  end
end
