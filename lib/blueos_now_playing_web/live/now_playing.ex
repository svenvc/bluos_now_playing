defmodule BlueOSNowPlayingWeb.NowPlaying do
  use BlueOSNowPlayingWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-sky-500 bg-cover bg-center h-screen grid justify-center">
      <h1 class="text-9xl font-bold text-neutral-50 mt-20 mb-20">Now Playing</h1>
      <p class="text-xl text-neutral-50 mb-20 font-mono">Seconds: {@secs}</p>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Process.send_after(self(), :update_secs, 1000)
    end

    {:ok, assign(socket, page_title: "Now Playing", secs: 0)}
  end

  @impl true
  def handle_info(:update_secs, socket) do
    %{assigns: %{secs: secs}} = socket

    Process.send_after(self(), :update_secs, 1000)

    {:noreply, assign(socket, secs: secs + 1)}
  end
end
