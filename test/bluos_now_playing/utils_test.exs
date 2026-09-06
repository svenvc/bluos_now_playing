defmodule BluOSNowPlaying.UtilsTest do
  use ExUnit.Case, async: true

  alias BluOSNowPlaying.Utils

  describe "ip_to_string/1" do
    test "formats a 4-tuple as a dotted quad" do
      assert Utils.ip_to_string({192, 168, 178, 95}) == "192.168.178.95"
    end

    test "handles octet boundaries" do
      assert Utils.ip_to_string({0, 0, 0, 0}) == "0.0.0.0"
      assert Utils.ip_to_string({255, 255, 255, 255}) == "255.255.255.255"
    end
  end

  describe "string_to_ip/1" do
    test "parses a dotted quad into a 4-tuple" do
      assert Utils.string_to_ip("192.168.178.95") == {192, 168, 178, 95}
    end

    test "parses octet boundaries" do
      assert Utils.string_to_ip("0.0.0.0") == {0, 0, 0, 0}
      assert Utils.string_to_ip("255.255.255.255") == {255, 255, 255, 255}
    end

    test "decodes zero-padded octets as integers" do
      assert Utils.string_to_ip("010.002.003.000") == {10, 2, 3, 0}
    end

    test "raises on malformed input" do
      assert_raise MatchError, fn -> Utils.string_to_ip("192.168.178.a") end
      assert_raise MatchError, fn -> Utils.string_to_ip("abc.def.ghi.jkl") end
    end
  end

  describe "format_time/1" do
    test "formats zero as MM:SS" do
      assert Utils.format_time(0) == "00:00"
    end

    test "formats sub-minute seconds" do
      assert Utils.format_time(9) == "00:09"
      assert Utils.format_time(59) == "00:59"
    end

    test "formats minutes as MM:SS" do
      assert Utils.format_time(60) == "01:00"
      assert Utils.format_time(61) == "01:01"
      assert Utils.format_time(671) == "11:11"
    end

    test "switches to H:MM:SS at exactly one hour" do
      assert Utils.format_time(3599) == "59:59"
      assert Utils.format_time(3600) == "01:00:00"
      assert Utils.format_time(7385) == "02:03:05"
    end

    test "keeps hours beyond two digits" do
      assert Utils.format_time(360_000) == "100:00:00"
    end

    test "handles negative input without raising" do
      assert Utils.format_time(-9) == "00:09"
      assert Utils.format_time(-3600) == "60:00"
    end
  end

  describe "round trip" do
    test "tuple -> string -> tuple is identity" do
      for ip <- [{0, 0, 0, 0}, {1, 2, 3, 4}, {192, 168, 178, 95}, {255, 255, 255, 255}] do
        assert ip |> Utils.ip_to_string() |> Utils.string_to_ip() == ip
      end
    end

    test "string -> tuple -> string is identity" do
      for string <- ["0.0.0.0", "1.2.3.4", "192.168.178.95", "255.255.255.255"] do
        assert string |> Utils.string_to_ip() |> Utils.ip_to_string() == string
      end
    end
  end
end
