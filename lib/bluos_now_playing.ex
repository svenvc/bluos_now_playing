defmodule BluOSNowPlaying do
  alias BluOSNowPlaying.API
  alias BluOSNowPlaying.Utils

  @moduledoc """
  BluOSNowPlaying is an interface to a BluOS (Bluesound) player
  to access the necessary data for a 'now playing' status.
  """

  @filename ".bluos_now_playing.json"
  @state_keys ~w(id name ip port)s

  @empty_state %{"id" => nil, "name" => nil, "ip" => nil, "port" => API.default_port()}

  def empty_state(), do: @empty_state

  def state_valid?(state) when is_map(state) do
    state |> Enum.all?(fn {_key, value} -> value end) &&
      @state_keys |> Enum.all?(fn key -> state |> Map.has_key?(key) end)
  end

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
      @empty_state
    end
  end

  def is_player_up?(state) when is_map(state) do
    case API.get_sync_status(state["ip"], state["port"]) do
      {:ok, sync_state} ->
        state["name"] == sync_state["name"]

      _ ->
        false
    end
  end

  @main_status_attributes ~w(title1 title2 title3 state totlen secs image quality streamFormat)s
  @integer_attributes ~w(secs totlen)s

  def process_status(map) do
    map = Map.take(map, @main_status_attributes)

    map =
      Enum.reduce(@integer_attributes, map, fn key, acc ->
        if Map.has_key?(map, key) do
          Map.update!(acc, key, &String.to_integer/1)
        else
          acc
        end
      end)
      |> Map.update("quality", "Q", &String.upcase/1)
      |> Map.update("streamFormat", "F", &String.upcase/1)

    map
    |> Map.put("state_label", state_label(map["state"]))
    |> Map.put("format", map["streamFormat"])
    |> Map.delete("streamFormat")
    |> Enum.into(%{}, fn {key, value} -> {String.to_atom(key), value} end)
  end

  defp state_label(state) when state in ~w(play stream)s, do: "PLAYING"
  defp state_label("stop"), do: "STOPPED"
  defp state_label("pause"), do: "PAUSED"
  defp state_label(_state), do: "UNKNOWN"
end
