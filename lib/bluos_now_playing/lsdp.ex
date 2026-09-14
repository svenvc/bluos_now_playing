defmodule BluOSNowPlaying.LSDP do
  @moduledoc """
  Support for the Lenbrook Service Discovery Protocol.

  LSDP packets are framed with a length-prefixed `"LSDP"` header (5 bytes,
  version 1) followed by a length-prefixed message block: `"A"` for announce,
  `"Q"` for query.
  """

  require Logger

  alias BluOSNowPlaying.Utils

  @port 11430

  @doc """
  Returns the UDP port used for LSDP discovery (`11430`).
  """
  def port, do: @port

  @doc """
  Opens a UDP socket on `port/0` with broadcasting enabled for discovery.

  Returns `{:ok, socket}` or `{:error, reason}` as returned by
  `:gen_udp.open/2`.
  """
  def socket() do
    :gen_udp.open(@port, [:binary, broadcast: true])
  end

  @doc """
  Closes an LSDP UDP socket.
  """
  def close(socket) do
    :gen_udp.close(socket)
  end

  @doc """
  Reads a length-prefixed block, returning `{block, rest}`.

  LSDP blocks are framed with a leading length byte. When `include_len?` is
  `true` (the default) that byte counts itself, so the payload is `len - 1`
  bytes; when `false` the payload is `len` bytes.
  """
  def extract_len_block(bytes, include_len? \\ true) when is_binary(bytes) do
    correction = if include_len?, do: -1, else: 0
    <<len::integer, block::binary-size(len + ^correction), rest::binary>> = bytes
    {block, rest}
  end

  @doc """
  Parses an announce body (starting with `"A"`) into `%{id, ip, records}`.

  `:id` is the player identifier, `:ip` the announced IP as a 4-tuple and
  `:records` a list of `%{class: integer, fields: %{name => value}}` maps. The
  record list is `[]` when the body carries none, or when they are unparseable.
  """
  def extract_announce_header(<<"A", bytes::binary>>) do
    {id, rest} = extract_len_block(bytes, false)
    {ip, rest} = extract_len_block(rest, false)
    ip = ip |> :binary.bin_to_list() |> List.to_tuple()
    %{id: id, ip: ip, records: extract_records_or_empty(rest)}
  end

  defp extract_records_or_empty(rest) do
    extract_records(rest)
  rescue
    _ -> []
  end

  defp extract_records(<<>>), do: []

  defp extract_records(<<count, rest::binary>>) do
    extract_records(rest, count, [])
  end

  defp extract_records(_rest, 0, acc), do: Enum.reverse(acc)

  defp extract_records(<<class::16, count, rest::binary>>, n, acc) do
    {pairs, rest} = extract_pairs(rest, count, [])
    record = %{class: class, fields: Map.new(pairs)}
    extract_records(rest, n - 1, [record | acc])
  end

  defp extract_pairs(rest, 0, acc), do: {Enum.reverse(acc), rest}

  defp extract_pairs(
         <<key_len, key::binary-size(key_len), val_len, val::binary-size(val_len), rest::binary>>,
         count,
         acc
       ) do
    extract_pairs(rest, count - 1, [{key, val} | acc])
  end

  @magic "LSDP"
  @version 1

  @doc """
  Returns the LSDP packet header: the `"LSDP"` magic followed by protocol
  version 1 (5 bytes in total).
  """
  def header, do: @magic <> <<@version>>

  @doc """
  Parses a full announce packet into `%{id: binary, ip: {a, b, c, d}, records: [...]}`.

  Raises `MatchError` on malformed input; consider `try_parse_announce/1`
  for a safe variant.
  """
  def parse_announce(packet) when is_binary(packet) do
    {@magic <> <<@version>>, body} = extract_len_block(packet)
    {announce, <<>>} = extract_len_block(body)
    extract_announce_header(announce)
  end

  @doc """
  Like `parse_announce/1`, but returns `:error` instead of raising on
  malformed input.
  """
  def try_parse_announce(packet) when is_binary(packet) do
    try do
      parse_announce(packet)
    rescue
      _ -> :error
    end
  end

  @doc """
  Parses a full query packet into `%{query: binary}`.

  Raises `MatchError` on malformed input; consider `try_parse_query/1`
  for a safe variant.
  """
  def parse_query(packet) when is_binary(packet) do
    {@magic <> <<@version>>, body} = extract_len_block(packet)
    {<<"Q", query::binary>>, <<>>} = extract_len_block(body)
    %{query: query}
  end

  @doc """
  Like `parse_query/1`, but returns `:error` instead of raising on malformed
  input.
  """
  def try_parse_query(packet) when is_binary(packet) do
    try do
      parse_query(packet)
    rescue
      _ -> :error
    end
  end

  @class_all <<255, 255>>

  @doc """
  Builds the length-prefixed `"Q"` query body requesting version 1 of class
  `0xFFFF` (all classes).
  """
  def query() do
    body = <<"Q", 1, @class_all::binary>>
    <<byte_size(body) + 1, body::binary>>
  end

  @doc """
  Builds a complete LSDP query packet (header + query body) ready to broadcast.
  """
  def query_packet(), do: <<byte_size(header()) + 1, header()::binary, query()::binary>>

  @doc """
  Sends `query_packet/0` to the broadcast address of every active interface
  through the given socket. Returns the packet sent.
  """
  def broadcast_query(socket) do
    packet = query_packet()

    for %{broadcast: ip} <- Utils.broadcast_interfaces() do
      Logger.info("Sending LSDP UDP query to #{inspect(ip)}")

      :gen_udp.send(socket, ip, @port, packet)
    end

    packet
  end
end
