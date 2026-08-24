defmodule BluOSNowPlaying.LSDP do
  @moduledoc """
  Support for the Lenbrook Service Discovery Protocol
  """

  @port 11430

  def port, do: @port

  def socket() do
    :gen_udp.open(@port)
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

  @class_all <<255, 255>>

  def query(), do: <<5, "Q", 1, @class_all>>

  @udp_broadcast_address {255, 255, 255, 255}

  def broadcast_query(count \\ 1) do
    {:ok, socket} = :gen_udp.open(0, [:binary, broadcast: true])
    packet = <<byte_size(header()) + 1, header()::binary, query()::binary>>

    1..count
    |> Enum.each(fn step ->
      :gen_udp.send(socket, @udp_broadcast_address, @port, packet)
      # space multiple packets progressively wider in time
      if step < count, do: Process.sleep((step + :rand.uniform(step)) * 250)
    end)

    :gen_udp.close(socket)
    packet
  end
end
