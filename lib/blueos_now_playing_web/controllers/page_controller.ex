defmodule BlueOSNowPlayingWeb.PageController do
  use BlueOSNowPlayingWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
