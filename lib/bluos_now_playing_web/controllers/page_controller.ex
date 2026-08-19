defmodule BluOSNowPlayingWeb.PageController do
  use BluOSNowPlayingWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
