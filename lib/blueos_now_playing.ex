defmodule BlueOSNowPlaying do

  alias BlueOSNowPlaying.API
  alias BlueOSNowPlaying.Utils

  @moduledoc """
  BlueOSNowPlaying is an interface to a BlueOS (Bluesound) player
  to access the necessary data for a 'now playing' status.
  """

  @lsdp_port 11430

  def lsdp_socket() do
    {:ok, socket} = :gen_udp.open(@lsdp_port)
    socket
  end

  def lsdp_close(socket) do
    :gen_udp.close(socket)
  end

  def extract_len_block(bytes, include_len? \\ true) when is_binary(bytes) do
    correction = if include_len?, do: -1, else: 0
    <<len::integer, block::binary-size(len + ^correction), rest::binary>> = bytes
    {block, rest}
  end

  def extract_announce_header("A" <> <<bytes::binary>>) do
    {id, rest} = extract_len_block(bytes, false)
    {ip, _} = extract_len_block(rest, false)
    ip = ip |> :binary.bin_to_list() |> List.to_tuple()
    %{id: id, ip: ip}
  end

  @lsdp_magic "LSDP"
  @lsdp_version 1

  def lsdp_header, do: @lsdp_magic <> <<@lsdp_version>>

  def lsdp_parse_announce(packet) when is_binary(packet) do
    {@lsdp_magic <> <<@lsdp_version>>, body} = BlueOSNowPlaying.extract_len_block(packet)
    {announce, <<>>} = BlueOSNowPlaying.extract_len_block(body)
    BlueOSNowPlaying.extract_announce_header(announce)
  end

  @lsdp_all <<255, 255>>

  def lsdp_query(), do: <<5>> <> "Q" <> <<1>> <> @lsdp_all

  @udp_broadcast_address {255, 255, 255, 255}

  def broadcast_query() do
    {:ok, socket} = :gen_udp.open(0, [:binary, broadcast: true])
    packet = <<byte_size(lsdp_header()) + 1>> <> lsdp_header() <> lsdp_query()
    :gen_udp.send(socket, @udp_broadcast_address, @lsdp_port, packet)
    :gen_udp.close(socket)
    packet
  end

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
