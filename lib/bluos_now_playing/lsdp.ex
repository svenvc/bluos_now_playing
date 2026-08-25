defmodule BluOSNowPlaying.LSDP do
  @moduledoc """
  Support for the Lenbrook Service Discovery Protocol
  """

  require Logger

  alias BluOSNowPlaying.Utils

  @port 11430

  def port, do: @port

  def socket() do
    :gen_udp.open(@port, [:binary, broadcast: true])
  end

  def close(socket) do
    :gen_udp.close(socket)
  end

  def extract_len_block(bytes, include_len? \\ true) when is_binary(bytes) do
    correction = if include_len?, do: -1, else: 0
    <<len::integer, block::binary-size(len + ^correction), rest::binary>> = bytes
    {block, rest}
  end

  def extract_announce_header(<<"A", bytes::binary>>) do
    {id, rest} = extract_len_block(bytes, false)
    {ip, _} = extract_len_block(rest, false)
    ip = ip |> :binary.bin_to_list() |> List.to_tuple()
    %{id: id, ip: ip}
  end

  @magic "LSDP"
  @version 1

  def header, do: @magic <> <<@version>>

  def parse_announce(packet) when is_binary(packet) do
    {@magic <> <<@version>>, body} = extract_len_block(packet)
    {announce, <<>>} = extract_len_block(body)
    extract_announce_header(announce)
  end

  def try_parse_announce(packet) when is_binary(packet) do
    try do
      parse_announce(packet)
    rescue
      _ -> :error
    end
  end

  def parse_query(packet) when is_binary(packet) do
    {@magic <> <<@version>>, body} = extract_len_block(packet)
    {<<"Q", query::binary>>, <<>>} = extract_len_block(body)
    %{query: query}
  end

  def try_parse_query(packet) when is_binary(packet) do
    try do
      parse_query(packet)
    rescue
      _ -> :error
    end
  end

  @class_all <<255, 255>>

  def query(), do: <<5, "Q", 1, @class_all>>

  def query_packet(), do: <<byte_size(header()) + 1, header()::binary, query()::binary>>

  def broadcast_query(socket) do
    packet = query_packet()

    for %{broadcast: ip} <- Utils.broadcast_interfaces() do
      Logger.info("Sending LSDP UDP query to #{inspect(ip)}")

      :gen_udp.send(socket, ip, @port, packet)
    end

    packet
  end
end
