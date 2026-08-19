defmodule BluOSNowPlaying.API do
  @moduledoc """
  Support for a couple of BluOS Custom Integration API calls.
  """

  import SweetXml

  alias BluOSNowPlaying.Utils

  @default_port 11000

  def default_port, do: @default_port

  @default_timeout 100

  def get_status(host, port \\ @default_port) when is_tuple(host) do
    hostname = host |> Utils.ip_to_string()
    url = "http://#{hostname}:#{port}/Status"

    response = Req.get!(url)

    response.body |> parse_status()
  end

  def get_status_long(etag, host, port \\ @default_port) when is_tuple(host) do
    hostname = host |> Utils.ip_to_string()
    url = "http://#{hostname}:#{port}/Status?etag=#{etag}&timeout=#{@default_timeout}"

    response =
      Req.get!(url,
        receive_timeout: (@default_timeout + 5) * 1000
      )

    response.body |> parse_status()
  end

  def get_sync_status(host, port \\ @default_port) when is_tuple(host) do
    hostname = host |> Utils.ip_to_string()
    url = "http://#{hostname}:#{port}/SyncStatus"

    response =
      Req.get!(url,
        connect_options: [timeout: 250],
        receive_timeout: 250,
        retry: false
      )

    response.body |> parse_status()
  end

  def parse_status(xml_string) when is_binary(xml_string) do
    xml_tree = SweetXml.parse(xml_string)

    children =
      xml_tree
      |> xpath(~x"/*/*"el)
      |> Enum.map(fn element ->
        {xpath(element, ~x"name()"s), xpath(element, ~x"text()"s)}
      end)
      |> Map.new()

    attributes =
      xml_tree
      |> xpath(~x"/*/@*"el)
      |> Enum.map(fn element ->
        {xpath(element, ~x"name()"s), xpath(element, ~x"string(.)"s)}
      end)
      |> Map.new()

    Map.merge(children, attributes)
  end
end
