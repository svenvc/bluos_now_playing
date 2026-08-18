defmodule BlueOSNowPlayingWeb.ImageProxy do
  use BlueOSNowPlayingWeb, :controller

  def proxy_img(conn, %{"url" => url}) do
    case Req.get("http://#{get_player_host_port()}#{url}") do
      {:ok, %Req.Response{status: 200} = response} ->
        [content_type] = response.headers["content-type"]

        if String.starts_with?(content_type, "image/") do
          conn
          |> put_resp_content_type(content_type)
          |> send_resp(200, response.body)
        else
          conn
          |> put_resp_content_type("image/png")
          |> send_resp(200, image_not_found_fallback())
        end

      _ ->
        conn
        |> put_resp_content_type("image/png")
        |> send_resp(200, image_not_found_fallback())
    end
  end

  def get_player_host_port() do
    Application.get_env(:blueos_now_playing, :player_host_port, "not-set:6666")
  end

  def set_player_host_port(host_port) do
    Application.put_env(:blueos_now_playing, :player_host_port, host_port)
  end

  def image_not_found_fallback() do
    Application.app_dir(:blueos_now_playing, "priv/static/images/image-not-found.png")
    |> File.read!()
  end
end
