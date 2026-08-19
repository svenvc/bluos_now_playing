defmodule BlueOSNowPlaying.LSDP do
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
    {@lsdp_magic <> <<@lsdp_version>>, body} = extract_len_block(packet)
    {announce, <<>>} = extract_len_block(body)
    extract_announce_header(announce)
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
