defmodule BluOSNowPlaying.LSDPTest do
  use ExUnit.Case, async: true

  alias BluOSNowPlaying.LSDP

  @known_query_packet <<6, 76, 83, 68, 80, 1, 5, 81, 1, 255, 255>>

  @known_announce_packet <<6, 76, 83, 68, 80, 1, 105, 65, 6, 144, 86, 130, 183, 31, 236, 4, 192,
                           168, 178, 95, 2, 0, 1, 5, 4, 110, 97, 109, 101, 9, 78, 79, 68, 69, 32,
                           78, 65, 78, 79, 4, 112, 111, 114, 116, 5, 49, 49, 48, 48, 48, 5, 109,
                           111, 100, 101, 108, 4, 78, 48, 51, 48, 7, 118, 101, 114, 115, 105, 111,
                           110, 7, 52, 46, 49, 54, 46, 50, 50, 2, 122, 115, 1, 48, 0, 4, 2, 4,
                           110, 97, 109, 101, 9, 78, 79, 68, 69, 32, 78, 65, 78, 79, 4, 112, 111,
                           114, 116, 5, 49, 49, 52, 51, 49>>

  describe "known wire packets" do
    test "the query fixture matches query_packet/0 byte-for-byte" do
      assert @known_query_packet == LSDP.query_packet()
    end

    test "parses the known query packet" do
      assert LSDP.try_parse_query(@known_query_packet) == %{query: <<1, 255, 255>>}
    end

    test "parses the known announce packet" do
      assert LSDP.try_parse_announce(@known_announce_packet) == %{
               id: <<144, 86, 130, 183, 31, 236>>,
               ip: {192, 168, 178, 95},
               records: [
                 %{
                   class: 0x0001,
                   fields: %{
                     "name" => "NODE NANO",
                     "port" => "11000",
                     "model" => "N030",
                     "version" => "4.16.22",
                     "zs" => "0"
                   }
                 },
                 %{class: 0x0004, fields: %{"name" => "NODE NANO", "port" => "11431"}}
               ]
             }
    end
  end

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

    test "reads an empty block when length is 1 (include_len? true)" do
      assert LSDP.extract_len_block(<<1, "rest">>) == {"", "rest"}
    end

    test "reads an empty block when length is 0 (include_len? false)" do
      assert LSDP.extract_len_block(<<0, "rest">>, false) == {"", "rest"}
    end

    test "raises on truncated input" do
      assert_raise MatchError, fn ->
        LSDP.extract_len_block(<<5, "ab">>)
      end
    end
  end

  describe "query/0" do
    test "prefixes the query body with its length counting itself" do
      assert <<len, payload::binary>> = LSDP.query()
      assert len == byte_size(payload) + 1
      assert byte_size(payload) == 4
    end

    test "contains version 1 and class 0xFFFF" do
      <<_len, "Q", 1, 255, 255>> = LSDP.query()
    end
  end

  describe "query_packet/0" do
    test "prefixes the whole packet with the header length plus one" do
      assert <<len, _::binary>> = LSDP.query_packet()
      assert len == byte_size(LSDP.header()) + 1
    end

    test "starts with the LSDP header after the length byte" do
      <<_len, header::binary-size(5), _rest::binary>> = LSDP.query_packet()
      assert header == LSDP.header()
    end

    test "round-trips through parse_query" do
      assert LSDP.try_parse_query(LSDP.query_packet()) == %{query: <<1, 255, 255>>}
    end
  end

  defp build_announce_packet(id, ip, records \\ <<>>) do
    ip_binary = ip |> Tuple.to_list() |> Enum.map(&<<&1>>) |> IO.iodata_to_binary()
    announce = "A" <> <<byte_size(id)>> <> id <> <<byte_size(ip_binary)>> <> ip_binary <> records
    body = <<byte_size(announce) + 1, announce::binary>>
    header = LSDP.header()
    <<byte_size(header) + 1, header::binary, body::binary>>
  end

  defp build_records(records) do
    bytes =
      for %{class: class, fields: fields} <- records, into: <<>> do
        pairs =
          for {key, val} <- fields, into: <<>> do
            <<byte_size(key), key::binary, byte_size(val), val::binary>>
          end

        <<class::16, map_size(fields), pairs::binary>>
      end

    <<length(records), bytes::binary>>
  end

  defp build_announce_record(class, fields), do: %{class: class, fields: fields}

  describe "parse_announce/1" do
    test "parses a packet built with the module's framing" do
      id = "0123456789AB"
      ip = {192, 168, 178, 95}

      assert LSDP.parse_announce(build_announce_packet(id, ip)) ==
               %{id: id, ip: ip, records: []}
    end

    test "handles a short ID" do
      assert LSDP.parse_announce(build_announce_packet("A", {10, 0, 0, 1})) ==
               %{id: "A", ip: {10, 0, 0, 1}, records: []}
    end

    test "handles a long ID" do
      id = String.duplicate("X", 200)

      assert LSDP.parse_announce(build_announce_packet(id, {127, 0, 0, 1})) ==
               %{id: id, ip: {127, 0, 0, 1}, records: []}
    end

    test "round-trips through try_parse_announce" do
      id = "0123456789AB"
      ip = {192, 168, 178, 95}

      assert LSDP.try_parse_announce(build_announce_packet(id, ip)) ==
               %{id: id, ip: ip, records: []}
    end

    test "parses announce records with key/value fields" do
      id = "0123456789AB"
      ip = {192, 168, 178, 95}

      records =
        build_records([
          build_announce_record(0x0001, %{"name" => "My Player", "port" => "11000"}),
          build_announce_record(0x0004, %{"name" => "My Player", "port" => "11431"})
        ])

      assert LSDP.parse_announce(build_announce_packet(id, ip, records)) == %{
               id: id,
               ip: ip,
               records: [
                 %{class: 0x0001, fields: %{"name" => "My Player", "port" => "11000"}},
                 %{class: 0x0004, fields: %{"name" => "My Player", "port" => "11431"}}
               ]
             }
    end

    test "is defensive: returns an empty records list on unparseable trailing bytes" do
      id = "0123456789AB"
      ip = {192, 168, 178, 95}

      assert LSDP.parse_announce(build_announce_packet(id, ip, <<255, 255>>)) ==
               %{id: id, ip: ip, records: []}
    end
  end

  describe "try_parse/1" do
    test "returns :error on garbage input" do
      assert LSDP.try_parse_announce("garbage") == :error
      assert LSDP.try_parse_query("garbage") == :error
    end

    test "returns :error on empty input" do
      assert LSDP.try_parse_announce(<<>>) == :error
      assert LSDP.try_parse_query(<<>>) == :error
    end

    test "returns :error on valid header but truncated body" do
      packet = <<byte_size(LSDP.header()) + 1, LSDP.header()::binary, 5, 0, 0>>
      assert LSDP.try_parse_announce(packet) == :error
      assert LSDP.try_parse_query(packet) == :error
    end
  end
end
