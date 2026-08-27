defmodule BluOSNowPlaying.Utils do
  def ip_to_string(ip) when is_tuple(ip) do
    ip
    |> Tuple.to_list()
    |> Enum.map(&to_string(&1))
    |> Enum.join(".")
  end

  def string_to_ip(string) when is_binary(string) do
    string
    |> String.split(".")
    |> Enum.map(fn s ->
      {i, ""} = Integer.parse(s)
      i
    end)
    |> List.to_tuple()
  end

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
