defmodule BluOSNowPlayingWeb.NowPlaying do
  use BluOSNowPlayingWeb, :live_view

  alias BluOSNowPlaying.Utils

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen h-screen overflow-hidden bg-black text-white">
      <!-- Artwork-derived atmosphere -->
      <div
        class="fixed inset-0 bg-cover bg-center scale-110 blur-3xl opacity-50"
        style={"background-image: url(#{@image})"}
      />
      <!-- Dark tint -->
      <div class="fixed inset-0 bg-black/10" />
      <!-- Everything visible -->
      <main class="relative z-10 h-full min-h-0 flex flex-col items-center px-6 py-4">
        <!-- Artwork area
             flex-1 means it takes whatever vertical space remains -->
        <div class="flex-1 min-h-0 w-full flex items-center justify-center">
          <img
            src={"#{@image}"}
            class="max-w-full max-h-full aspect-square object-cover rounded-lg shadow-2xl"
          />
        </div>
        <!-- Track information -->
        <section class="shrink-0 w-full max-w-3xl text-center mt-4">
          <h1 class="text-xl font-semibold leading-tight">
            {@title1}
          </h1>
          <p class="text-lg text-white/80">
            {@title2}
          </p>
          <p class="text-base text-white/55">
            {@title3}
          </p>
          <!-- Technical information -->
          <div class="flex justify-center items-center gap-3 mt-2 text-xs text-white/25">
            <span>{@quality}</span>
            <span>•</span>
            <span>{@format}</span>
            <span>•</span>
            <span>{@player_name}</span>
            <span>•</span>
            <span>{@state_label}</span>
          </div>
          <!-- Progress -->
          <div class="w-full mt-3 pb-1 font-mono">
            <div class="flex justify-between text-sm text-white/60 mb-1">
              <span>00:00</span>
              <span>{@total}</span>
            </div>
            <div class="h-1.5 w-full rounded-full bg-white/25 overflow-hidden">
              <div
                class="h-full rounded-full bg-white/90"
                style={"width: #{@progress}%"}
              />
            </div>
            <div class="flex justify-between text-sm text-white/60 mt-1">
              <span>{@current}</span>
              <span>{@remaining}</span>
            </div>
          </div>
        </section>
      </main>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Process.send_after(self(), :update_secs, 1000)
    end

    {:ok,
     socket
     |> assign(
       page_title: "BluOS • Now Playing",
       player_name: "NODE NANO",
       image: maybe_proxy_img("/Artwork?service=Qobuz&songid=Qobuz%3A47683566"),
       title1: "Shine On You Crazy Diamond (Pts. 6-9)",
       title2: "Pink Floyd",
       title3: "Wish You Were Here",
       quality: "HD",
       format: "FLAC 24/96",
       totlen: 743,
       state: "play",
       state_label: "PLAYING",
       secs: 12
     )
     |> assign_progress()}
  end

  def assign_progress(socket) do
    %{assigns: %{secs: secs, totlen: totlen}} = socket

    socket
    |> assign(
      progress: Float.round(secs / totlen * 100, 1),
      current: Utils.format_time(secs),
      remaining: Utils.format_time(totlen - secs),
      total: Utils.format_time(totlen)
    )
  end

  @impl true
  def handle_info(:update_secs, socket) do
    %{assigns: %{secs: secs, totlen: totlen}} = socket

    Process.send_after(self(), :update_secs, 1000)

    {:noreply, assign(socket, secs: min(secs + 1, totlen)) |> assign_progress()}
  end

  def maybe_proxy_img("https://" <> _ = img_url) do
    img_url
  end

  def maybe_proxy_img("http://" <> _ = img_url) do
    img_url
  end

  def maybe_proxy_img(img_url) do
    "/proxy-img?#{URI.encode_query(%{url: img_url})}"
  end
end
