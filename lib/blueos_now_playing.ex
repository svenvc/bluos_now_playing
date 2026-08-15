defmodule BlueOSNowPlaying do
  import SweetXml

  @moduledoc """
  BlueOSNowPlaying is an interface to a BlueOS (Bluesound) player
  to access the necessary data for a 'now playing' status.
  """

  @default_port 11000
  @default_timeout 100

  def get_status(host, port \\ @default_port) when is_tuple(host) do
    hostname = host |> Tuple.to_list() |> Enum.map(&to_string(&1)) |> Enum.join(".")
    url = "http://#{hostname}:#{port}/Status"
    response = Req.get!(url)
    response.body |> parse_status()
  end

  def get_status_long(etag, host, port \\ @default_port) when is_tuple(host) do
    hostname = host |> Tuple.to_list() |> Enum.map(&to_string(&1)) |> Enum.join(".")
    url = "http://#{hostname}:#{port}/Status?etag=#{etag}&timeout=#{@default_timeout}"
    response = Req.get!(url, receive_timeout: (@default_timeout + 5) * 1000)
    response.body |> parse_status()
  end

  def parse_status(xml_string) when is_binary(xml_string) do
    xml_tree = SweetXml.parse(xml_string)

    xml_tree
    |> xpath(~x"/*/*"el)
    |> Enum.map(fn element ->
      {
        SweetXml.xpath(element, ~x"name()"s),
        SweetXml.xpath(element, ~x"text()"s)
      }
    end)
    |> Map.new()
    |> Map.put("etag", xpath(xml_tree, ~x"/*/@etag"s))
  end
end
