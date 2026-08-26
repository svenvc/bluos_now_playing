defmodule BluOSNowPlaying.API do
  @moduledoc """
  Support for a couple of BluOS Custom Integration API calls.
  """

  import SweetXml

  require Logger

  alias BluOSNowPlaying.Utils

  @default_port 11000

  def default_port, do: @default_port

  def get_status(host, port \\ @default_port)

  def get_status(nil, _), do: {:error, :no_ip}

  def get_status(host, port) when is_tuple(host) do
    hostname = host |> Utils.ip_to_string()
    url = "http://#{hostname}:#{port}/Status"

    Logger.info("GET #{url}")

    case Req.get(url) do
      {:ok,
       %Req.Response{
         status: 200,
         headers: %{
           "content-type" => ["application/xml"]
         },
         body: body
       }} ->
        {:ok, parse_status(body)}

      {:error, error} ->
        {:error, error}
    end
  end

  @default_timeout 60

  def get_status_long(etag, host, port \\ @default_port)

  def get_status_long(_, nil, _), do: {:error, :no_ip}

  def get_status_long(etag, host, port) when is_tuple(host) do
    hostname = host |> Utils.ip_to_string()
    url = "http://#{hostname}:#{port}/Status?etag=#{etag}&timeout=#{@default_timeout}"

    Logger.info("GET #{url}")

    case Req.get(url,
           receive_timeout: (@default_timeout + 5) * 1000
         ) do
      {:ok,
       %Req.Response{
         status: 200,
         headers: %{
           "content-type" => ["application/xml"]
         },
         body: body
       }} ->
        {:ok, parse_status(body)}

      {:error, error} ->
        {:error, error}
    end
  end

  def get_sync_status(host, port \\ @default_port)

  def get_sync_status(nil, _), do: {:error, :no_ip}

  def get_sync_status(host, port) when is_tuple(host) do
    hostname = host |> Utils.ip_to_string()
    url = "http://#{hostname}:#{port}/SyncStatus"

    Logger.info("GET #{url}")

    case Req.get(url,
           connect_options: [timeout: 250],
           receive_timeout: 250,
           retry: false
         ) do
      {:ok,
       %Req.Response{
         status: 200,
         headers: %{
           "content-type" => ["application/xml"]
         },
         body: body
       }} ->
        {:ok, parse_status(body)}

      {:error, error} ->
        {:error, error}
    end
  end

  def toggle_play_pause(host, port \\ @default_port)

  def toggle_play_pause(nil, _), do: {:error, :no_ip}

  def toggle_play_pause(host, port) when is_tuple(host) do
    hostname = host |> Utils.ip_to_string()
    url = "http://#{hostname}:#{port}/Pause?toggle=1"

    Logger.info("GET #{url}")

    case Req.get(url) do
      {:ok,
       %Req.Response{
         status: 200,
         headers: %{
           "content-type" => ["application/xml"]
         },
         body: body
       }} ->
        {:ok, xpath(body, ~x"text()"s)}

      {:error, error} ->
        {:error, error}
    end
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
