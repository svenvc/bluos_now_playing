defmodule BlueOSNowPlayingWeb.NowPlaying do
  use BlueOSNowPlayingWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-sky-500 bg-cover bg-center h-screen grid justify-center">
      <h1 class="text-9xl font-bold text-neutral-50 mt-20 mb-20">Now Playing</h1>
      <p class="text-xl text-neutral-50 mb-20 font-mono">Server clock: {@server_clock}</p>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    now = DateTime.utc_now(:second)

    if connected?(socket) do
      Process.send_after(self(), :update_clock, 1000)
    end

    {:ok, assign(socket, page_title: "Now Playing", server_clock: now)}
  end

  @impl true
  def handle_info(:update_clock, socket) do
    now = DateTime.utc_now(:second)

    Process.send_after(self(), :update_clock, 1000)

    {:noreply, assign(socket, server_clock: now)}
  end
end
