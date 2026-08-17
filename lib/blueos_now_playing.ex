defmodule BlueOSNowPlaying do
  import SweetXml

  @moduledoc """
  BlueOSNowPlaying is an interface to a BlueOS (Bluesound) player
  to access the necessary data for a 'now playing' status.
  """

  @default_port 11000
  @default_timeout 100

  def get_status(host, port \\ @default_port) when is_tuple(host) do
    hostname = host |> ip_to_string()
    url = "http://#{hostname}:#{port}/Status"
    response = Req.get!(url)
    response.body |> parse_status()
  end

  def get_status_long(etag, host, port \\ @default_port) when is_tuple(host) do
    hostname = host |> ip_to_string()
    url = "http://#{hostname}:#{port}/Status?etag=#{etag}&timeout=#{@default_timeout}"
    response = Req.get!(url, receive_timeout: (@default_timeout + 5) * 1000)
    response.body |> parse_status()
  end

  def get_sync_status(host, port \\ @default_port) when is_tuple(host) do
    hostname = host |> ip_to_string()
    url = "http://#{hostname}:#{port}/SyncStatus"
    response = Req.get!(url)
    response.body |> parse_status()
  end

  def ip_to_string(ip) when is_tuple(ip) do
    ip |> Tuple.to_list() |> Enum.map(&to_string(&1)) |> Enum.join(".")
  end

  def parse_status(xml_string) when is_binary(xml_string) do
    xml_tree = SweetXml.parse(xml_string)

    children =
      xml_tree
      |> xpath(~x"/*/*"el)
      |> Enum.map(fn element ->
        {xpath(element, ~x"name()"s), xpath(element, ~x"text()"s)}
      end)
      |> Map.new()

    attributes =
      xml_tree
      |> xpath(~x"/*/@*"el)
      |> Enum.map(fn element ->
        {xpath(element, ~x"name()"s), xpath(element, ~x"string(.)"s)}
      end)
      |> Map.new()

    Map.merge(children, attributes)
  end

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
end
