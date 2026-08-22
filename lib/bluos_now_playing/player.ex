defmodule BluOSNowPlaying.Player do
  use GenServer

  require Logger

  @empty_player_status %{
    player_name: "BluOS Player",
    image: "/image-not-found.png",
    title1: "-",
    title2: "--",
    title3: "---",
    quality: "Q",
    format: "F",
    totlen: 0,
    state: "stop",
    state_label: "STOPPED",
    secs: 0
  }

  @impl true
  def init(init_arg) do
    Logger.info("Player init #{inspect(init_arg)}")

    initial_state =
      %{
        player_core_state: %{},
        player_sync_status_raw: %{},
        player_status_raw: %{},
        player_status: @empty_player_status
      }

    initial_state =
      case init_arg do
        :saved -> initial_state |> maybe_load_saved_core_state()
        :none -> initial_state
      end

    {:ok, initial_state, {:continue, :start}}
  end

  @impl true
  def handle_continue(:start, state) do
    Logger.info("Player continue :start")
    {:noreply, state}
  end

  @impl true
  def handle_call({:status, refresh?}, _from, state) do
    Logger.info("Player call :status refresh=#{refresh?}")

    state =
      if refresh? do
        load_status(state)
      else
        state
      end

    {:reply, state.player_status, state}
  end

  @impl true
  def handle_call(:host_port, _from, state) do
    Logger.info("Player call :host_port")
    host = state.player_core_state["ip"]
    port = state.player_core_state["port"]

    host_port =
      if host && port do
        "#{host |> BluOSNowPlaying.Utils.ip_to_string()}:#{port}"
      else
        nil
      end

    {:reply, host_port, state}
  end

  @impl true
  def handle_cast(:stop, state) do
    Logger.info("Player :stop")
    {:stop, :normal, state}
  end

  @impl true
  def terminate(reason, _state) do
    Logger.info("Player stopped #{inspect(reason)}")
  end

  @impl true
  def handle_info(:yo, state) do
    Logger.info("Player :yo")
    {:noreply, state}
  end

  # Internal

  def maybe_load_saved_core_state(state) do
    core_state = BluOSNowPlaying.load_state()

    if core_state["id"] && BluOSNowPlaying.is_player_up?(core_state) do
      case BluOSNowPlaying.API.get_sync_status(core_state["ip"]) do
        {:ok, sync_status} ->
          state
          |> Map.put(:player_core_state, core_state)
          |> Map.put(:player_sync_status_raw, sync_status)
          |> load_status()

        _ ->
          state
      end
    else
      state
    end
  end

  def load_status(state) do
    case BluOSNowPlaying.API.get_status(state.player_core_state["ip"]) do
      {:ok, status} ->
        processed_status =
          status
          |> BluOSNowPlaying.process_status()
          |> Map.put(:player_name, state.player_sync_status_raw["name"])

        state
        |> Map.put(:player_status_raw, status)
        |> Map.put(:player_status, processed_status)

      _ ->
        state
    end
  end

  # API

  def start(init_arg \\ :saved) do
    Logger.info("Binding new #{inspect(__MODULE__)}")
    GenServer.start(__MODULE__, init_arg, name: __MODULE__)
  end

  def stop() do
    GenServer.cast(__MODULE__, :stop)
  end

  def host_port() do
    GenServer.call(__MODULE__, :host_port)
  end

  def status(refresh? \\ false) do
    GenServer.call(__MODULE__, {:status, refresh?})
  end
end
