defmodule BluOSNowPlaying.Player do
  use GenServer

  require Logger

  alias BluOSNowPlaying.API
  alias BluOSNowPlaying.LSDP
  alias BluOSNowPlaying.Utils

  @empty_player_status %{
    player_name: "BluOS Player",
    image: "/image-not-found.png",
    title1: "",
    title2: "",
    title3: "",
    quality: "Q",
    format: "F",
    totlen: 0,
    state: "stop",
    state_label: "STOPPED",
    secs: 0
  }

  def empty_player_status(), do: @empty_player_status

  @impl true
  def init(init_arg) do
    Logger.info("Player init #{inspect(init_arg)}")

    initial_state =
      %{
        player_core_state: BluOSNowPlaying.empty_state(),
        player_sync_status_raw: %{},
        player_status_raw: %{},
        player_status: @empty_player_status
      }

    initial_state =
      case init_arg do
        :saved -> initial_state |> maybe_load_saved_core_state()
        :none -> initial_state
        {:ip, ip} -> initial_state |> maybe_use_ip(ip)
      end

    {:ok, initial_state, {:continue, :start}}
  end

  @impl true
  def handle_continue(:start, state) do
    Logger.info("Player continue :start")

    new_state =
      state
      |> invoke_task_update_status_long()
      |> maybe_invoke_task_discovery()

    {:noreply, new_state}
  end

  @impl true
  def handle_continue(:broadcast_update_status, state) do
    Logger.info("Player continue :broadcast_update_status")

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
  def handle_call(:core_state, _from, state) do
    Logger.info("Player call :core_state")

    {:reply, state.player_core_state, state}
  end

  @impl true
  def handle_call(:toggle_play_pause, _from, state) do
    Logger.info("Player call :toggle_play_pause")

    case API.toggle_play_pause(ip(state), port(state)) do
      {:ok, play_pause_state} -> {:reply, play_pause_state, state}
      {:error, _error} -> {:reply, :error, state}
    end
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

  @minimal_fields ~w(state secs totlen etag)

  @impl true
  def handle_info({:update_status, new_status}, state) do
    new_state =
      if is_nil(new_status) do
        Logger.info("Player :update_status no change")

        state
      else
        minimal_status = new_status |> Map.take(@minimal_fields)

        Logger.info("Player :update_status new_status=#{inspect(minimal_status)}")

        state |> update_status(new_status)
      end

    invoke_task_update_status_long(new_state)

    {:noreply, new_state, {:continue, :broadcast_update_status}}
  end

  @impl true
  def handle_info({:udp, _socket, ip, port, bytes}, state) do
    Logger.info(
      "Player received UDP of #{byte_size(bytes)} bytes from #{Utils.ip_to_string(ip)}:#{port}"
    )

    case LSDP.try_parse_announce(bytes) do
      %{} = announce ->
        Logger.info("Player received LSDP announce #{inspect(announce)}")

        {:noreply, state |> process_announce(announce), {:continue, :broadcast_update_status}}

      :error ->
        case LSDP.try_parse_query(bytes) do
          %{} = _query ->
            Logger.info("Player received LSDP query")

          :error ->
            Logger.info("Player received unknown LSDP packet #{inspect(bytes)}")
        end

        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:broadcast_query, state) do
    Logger.info("Player :broadcast_query")

    if state.player_core_state |> BluOSNowPlaying.state_valid?() do
      Logger.info("Player core state is valid, not sending broadcast query")
    else
      LSDP.broadcast_query(state.socket)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:end_discovery, state) do
    Logger.info("Player :end_discovery")

    LSDP.close(state.socket)

    Logger.info("Player no longer listening for LSDP UDP broadcasts")

    if state.player_core_state |> BluOSNowPlaying.state_valid?() do
      Logger.info("Player core state is valid")
    else
      Logger.info("Player discovery failed")
    end

    {:noreply, state |> Map.delete(:socket)}
  end

  def start_link(opts) do
    env_player_ip = env_player_ip()

    init_arg =
      if env_player_ip do
        {:ip, env_player_ip}
      else
        opts[:init_arg] || :saved
      end

    name = opts[:name] || __MODULE__

    GenServer.start_link(__MODULE__, init_arg, name: name)
  end

  # Internal

  def ip(state), do: state.player_core_state["ip"]

  def port(state), do: state.player_core_state["port"]

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
    case API.get_status(ip(state), port(state)) do
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

  def maybe_use_ip(state, ip) do
    case API.get_sync_status(ip) do
      {:ok, sync_status} ->
        Logger.info("Player successfully resolved #{Utils.ip_to_string(ip)}")

        core_state =
          state.player_core_state
          |> Map.put("ip", ip)
          |> Map.put("name", sync_status["name"])
          |> Map.put("id", extract_id(sync_status))

        BluOSNowPlaying.save_state(core_state)

        state
        |> Map.put(:player_core_state, core_state)
        |> Map.put(:player_sync_status_raw, sync_status)
        |> load_status()

      _ ->
        Logger.info("Player failed to resolved #{Utils.ip_to_string(ip)}")

        state
    end
  end

  def invoke_task_update_status_long(state) do
    start_task_update_status_long(state.player_status_raw["etag"], ip(state), port(state))

    state
  end

  def start_task_update_status_long(_, nil, _) do
    Logger.info("Player delaying get_status_long by 10s")

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

  def maybe_invoke_task_discovery(state) do
    if state.player_core_state |> BluOSNowPlaying.state_valid?() do
      Logger.info("Player core state is valid, did not start player discovery")

      state
    else
      invoke_task_discovery(state)
    end
  end

  @number_of_broadcasts 7

  def invoke_task_discovery(state) do
    case LSDP.socket() do
      {:ok, socket} ->
        Logger.info("Player listening for LSDP UDP broadcasts")

        parent = self()
        new_state = Map.put(state, :socket, socket)

        Task.start(fn ->
          1..@number_of_broadcasts
          |> Enum.each(fn step ->
            send(parent, :broadcast_query)
            # space multiple packets progressively wider in time
            Process.sleep((step + :rand.uniform(step)) * 250)
          end)

          send(parent, :end_discovery)
        end)

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
          |> load_status()
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

  @bluos_player_ip_key "BLUOS_PLAYER_IP"

  def env_player_ip() do
    try do
      System.get_env(@bluos_player_ip_key) |> Utils.string_to_ip()
    rescue
      _ -> nil
    end
  end

  def extract_id(sync_status) do
    try do
      sync_status |> Map.get("mac") |> String.split(":") |> Enum.join() |> Base.decode16!()
    rescue
      _ -> sync_status |> Map.get("id")
    end
  end

  # API

  def start(init_arg \\ :saved) do
    GenServer.start(__MODULE__, init_arg, name: __MODULE__)
  end

  def stop() do
    GenServer.cast(__MODULE__, :stop)
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

  # derived API

  def ip(), do: core_state()["ip"]

  def port(), do: core_state()["port"]

  def host_port() do
    %{"ip" => ip, "port" => port} = core_state()

    if ip && port do
      "#{ip |> Utils.ip_to_string()}:#{port}"
    else
      nil
    end
  end

  def has_core_state?() do
    core_state() |> BluOSNowPlaying.state_valid?()
  end

  def status_text(refresh? \\ false) do
    status = status(refresh?)
    secs = status[:secs]
    totlen = status[:totlen]
    progress = Float.round(if(totlen == 0, do: 0.0, else: secs / totlen * 100), 1)
    current = Utils.format_time(secs)
    remaining = Utils.format_time(totlen - secs)
    total = Utils.format_time(totlen)

    """
    #{status[:title1]} • #{status[:title2]} • #{status[:title3]}
    #{status[:quality]} • #{status[:format]} • #{status[:player_name]} • #{status[:state_label]}
    #{secs}/#{totlen} • #{current}/#{total} • -#{remaining} • #{progress}%
    """
  end

  def print_status(refresh? \\ false) do
    IO.puts(status_text(refresh?))
  end
end
