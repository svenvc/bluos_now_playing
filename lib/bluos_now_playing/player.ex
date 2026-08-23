defmodule BluOSNowPlaying.Player do
  use GenServer

  require Logger

  alias BluOSNowPlaying.API
  alias BluOSNowPlaying.LSDP
  alias BluOSNowPlaying.Utils

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

    new_state =
      state
      |> invoke_task_update_status_long()
      |> invoke_task_discovery()

    {:noreply, new_state}
  end

  @impl true
  def handle_continue(:broadcast_update_status, state) do
    Logger.info("Player continue :broadcast_state_update")

    Phoenix.PubSub.broadcast(
      BluOSNowPlaying.PubSub,
      "player",
      {:update_status, state.player_status}
    )

    {:noreply, state}
  end

  @impl true
  def handle_call({:status, refresh?}, _from, state) do
    Logger.info("Player call :status refresh?=#{refresh?}")

    new_state =
      if refresh? do
        load_status(state)
      else
        state
      end

    {:reply, new_state.player_status, new_state}
  end

  @impl true
  def handle_call(:host_port, _from, state) do
    Logger.info("Player call :host_port")
    host = state.player_core_state["ip"]
    port = state.player_core_state["port"]

    host_port =
      if host && port do
        "#{host |> Utils.ip_to_string()}:#{port}"
      else
        nil
      end

    {:reply, host_port, state}
  end

  @impl true
  def handle_call(:toggle_play_pause, _from, state) do
    Logger.info("Player call :toggle_play_pause")

    host = state.player_core_state["ip"]
    port = state.player_core_state["port"]

    case API.toggle_play_pause(host, port) do
      {:ok, play_pause_state} -> {:reply, play_pause_state, state}
      {:error, _error} -> {:reply, :error, state}
    end
  end

  @impl true
  def handle_call(:core_state, _from, state) do
    Logger.info("Player call :core_state")

    {:reply, state.player_core_state, state}
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
  def handle_info({:update_status, new_status}, state) do
    Logger.info(
      "Player :update_status new_status=#{inspect(new_status |> Map.take(~w(state secs totlen etag)))}"
    )

    new_state = state |> update_status(new_status)

    invoke_task_update_status_long(new_state)

    {:noreply, new_state, {:continue, :broadcast_update_status}}
  end

  @impl true
  def handle_info({:udp, _socket, ip, port, bytes}, state) do
    Logger.info("Player received UDP #{inspect(bytes)} from #{Utils.ip_to_string(ip)}:#{port}")

    case LSDP.try_parse_announce(bytes |> :binary.list_to_bin()) do
      %{} = announce ->
        Logger.info("Player received LSDP announce #{inspect(announce)}")

        {:noreply, state |> process_announce(announce), {:continue, :broadcast_update_status}}

      :error ->
        {:noreply, state}
    end
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts[:init_arg] || :saved, name: opts[:name] || __MODULE__)
  end

  # Internal

  def maybe_load_saved_core_state(state) do
    core_state = BluOSNowPlaying.load_state()

    case API.get_sync_status(core_state["ip"]) do
      {:ok, sync_status} ->
        if core_state["name"] == sync_status["name"] do
          state
          |> Map.put(:player_core_state, core_state)
          |> Map.put(:player_sync_status_raw, sync_status)
          |> load_status()
        else
          state
        end

      _ ->
        state
    end
  end

  def load_status(state) do
    case API.get_status(state.player_core_state["ip"]) do
      {:ok, status} ->
        state |> update_status(status)

      _ ->
        state
    end
  end

  def update_status(state, nil), do: state

  def update_status(state, status) do
    processed_status =
      status
      |> BluOSNowPlaying.process_status()
      |> Map.put(:player_name, state.player_sync_status_raw["name"])

    state
    |> Map.put(:player_status_raw, status)
    |> Map.put(:player_status, processed_status)
  end

  def invoke_task_update_status_long(state) do
    host = state.player_core_state["ip"]
    port = state.player_core_state["port"]
    etag = state.player_status_raw["etag"]

    start_task_update_status_long(etag, host, port)

    state
  end

  def start_task_update_status_long(_, nil, _) do
    Process.send_after(self(), {:update_status, nil}, 10_000)
  end

  def start_task_update_status_long(etag, host, port) do
    parent = self()

    Task.start(fn ->
      case API.get_status_long(etag, host, port) do
        {:ok, status} -> send(parent, {:update_status, status})
        _ -> send(parent, {:update_status, nil})
      end
    end)
  end

  def invoke_task_discovery(state) do
    case LSDP.socket() do
      {:ok, socket} ->
        Logger.info("Player listening for LSDP UDP broadcasts")

        new_state = Map.put(state, :socket, socket)

        Task.start(fn -> LSDP.broadcast_query(7) end)

        new_state

      _ ->
        Logger.info("Player failed to open LSDP UDP socket, in use ?")

        state
    end
  end

  def process_announce(state, announce) do
    ip = announce[:ip]
    id = announce[:id]

    case API.get_sync_status(ip) do
      {:ok, sync_status} ->
        core_state = %{
          "id" => id,
          "ip" => ip,
          "port" => API.default_port(),
          "name" => sync_status["name"]
        }

        if core_state == state.player_core_state do
          Logger.info("Player :core_state unchanged")

          state
        else
          Logger.info("Player new :core_state #{inspect(core_state)}")

          BluOSNowPlaying.save_state(core_state)

          state
          |> Map.put(:player_core_state, core_state)
          |> Map.put(:player_sync_status_raw, sync_status)
          |> load_status()
        end

      _ ->
        state
    end
  end

  # API

  def start(init_arg \\ :saved) do
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

  def core_state() do
    GenServer.call(__MODULE__, :core_state)
  end

  def toggle_play_pause() do
    GenServer.call(__MODULE__, :toggle_play_pause)
  end
end
