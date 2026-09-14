defmodule BluOSNowPlaying.LSDPTest do
  use ExUnit.Case, async: true

  alias BluOSNowPlaying.LSDP

  describe "header/0" do
    test "is the LSDP magic followed by version 1" do
      assert LSDP.header() == "LSDP" <> <<1>>
      assert byte_size(LSDP.header()) == 5
    end
  end

  describe "extract_len_block/2" do
    test "reads a length-prefixed block counting the length byte by default" do
      assert LSDP.extract_len_block(<<4, "abc", "rest">>) == {"abc", "rest"}
      assert LSDP.extract_len_block(<<3, "ab">>) == {"ab", ""}
    end

    test "reads a length-prefixed block not counting the length byte with false" do
      assert LSDP.extract_len_block(<<3, "abc", "rest">>, false) == {"abc", "rest"}
    end
  end

  describe "query/0" do
    test "prefixes the query body with its length counting itself" do
      assert <<len, payload::binary>> = LSDP.query()
      assert len == byte_size(payload) + 1
      assert byte_size(payload) == 4
    end
  end

  describe "query_packet/0" do
    test "prefixes the whole packet with the header length plus one" do
      assert <<len, _::binary>> = LSDP.query_packet()
      assert len == byte_size(LSDP.header()) + 1
    end

    test "round-trips through parse_query" do
      assert LSDP.try_parse_query(LSDP.query_packet()) == %{query: <<1, 255, 255>>}
    end
  end

  describe "parse_announce/1" do
    test "parses a packet built with the module's framing" do
      id = "0123456789AB"
      ip = {192, 168, 178, 95}
      ip_binary = ip |> Tuple.to_list() |> Enum.map(&<<&1>>) |> IO.iodata_to_binary()

      announce = "A" <> <<byte_size(id)>> <> id <> <<byte_size(ip_binary)>> <> ip_binary
      body = <<byte_size(announce) + 1, announce::binary>>
      header = LSDP.header()
      packet = <<byte_size(header) + 1, header::binary, body::binary>>

      assert LSDP.parse_announce(packet) == %{id: id, ip: ip}
    end
  end

  describe "try_parse/1" do
    test "returns :error on garbage input" do
      assert LSDP.try_parse_announce("garbage") == :error
      assert LSDP.try_parse_query("garbage") == :error
    end
  end
end
