defmodule BluOSNowPlaying.Utils do
  @moduledoc """
  Small helper functions shared across the application.
  """

  @doc """
  Converts an IP address tuple to a dotted decimal string, e.g.
  `{192, 168, 178, 95}` → `"192.168.178.95"`.
  """
  def ip_to_string(ip) when is_tuple(ip) do
    ip
    |> Tuple.to_list()
    |> Enum.map(&to_string(&1))
    |> Enum.join(".")
  end

  @doc """
  Converts a dotted decimal string to an IP address tuple, e.g.
  `"192.168.178.95"` → `{192, 168, 178, 95}`.

  Raises `MatchError` when the string is not a well-formed IP address.
  """
  def string_to_ip(string) when is_binary(string) do
    string
    |> String.split(".")
    |> Enum.map(fn s ->
      {i, ""} = Integer.parse(s)
      i
    end)
    |> List.to_tuple()
  end

  @doc """
  Formats a number of seconds as `"MM:SS"`, or `"HH:MM:SS"` from 3600 seconds
  onward. Negative values are formatted as if positive.
  """
  def format_time(secs) when is_integer(secs) do
    if secs < 3600 do
      minutes = div(secs, 60)
      seconds = rem(secs, 60)
      "#{format_2digits(minutes)}:#{format_2digits(seconds)}"
    else
      hours = div(secs, 3600)
      rem = rem(secs, 3600)
      minutes = div(rem, 60)
      seconds = rem(rem, 60)
      "#{format_2digits(hours)}:#{format_2digits(minutes)}:#{format_2digits(seconds)}"
    end
  end

  defp format_2digits(int) when is_integer(int) and int >= 0 do
    int |> to_string() |> String.pad_leading(2, "0")
  end

  defp format_2digits(int) when is_integer(int) and int < 0 do
    format_2digits(abs(int))
  end

  defp format_2digits(_), do: ""

  @doc """
  Joins the truthy values of an enumerable with the given joiner, skipping
  `nil`, `false`, and other falsy entries.
  """
  def join_not_nil(enumerable, joiner) do
    enumerable |> Enum.filter(fn x -> x end) |> Enum.join(joiner)
  end

  @doc """
  Returns a list of `%{interface: name, address: ip, broadcast: ip}` maps for
  every active, up-running interface with a broadcast IPv4 address.

  Used to determine where to send LSDP discovery broadcasts.
  """
  def broadcast_interfaces do
    {:ok, interfaces} = :inet.getifaddrs()

    for {name, info} <- interfaces,
        :up in Keyword.get(info, :flags, []),
        :running in Keyword.get(info, :flags, []),
        :broadcast in Keyword.get(info, :flags, []),
        address <- Keyword.get_values(info, :addr),
        ipv4?(address),
        broadcast <- [Keyword.get(info, :broadaddr)],
        ipv4?(broadcast) do
      %{
        interface: name,
        address: address,
        broadcast: broadcast
      }
    end
  end

  defp ipv4?({a, b, c, d})
       when a in 0..255 and
              b in 0..255 and
              c in 0..255 and
              d in 0..255,
       do: true

  defp ipv4?(_), do: false
end
