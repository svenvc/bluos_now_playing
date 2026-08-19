defmodule BlueOSNowPlaying.Player do
  use GenServer

  require Logger

  @impl true
  def init(_init_arg) do
    Logger.info("Starting")
    {:ok, %{secs: 0}, {:continue, :start}}
  end

  @impl true
  def handle_continue(:start, state) do
    Logger.info("Start")
    {:noreply, state}
  end

  @impl true
  def handle_call(:secs, _from, state) do
    Logger.info("Call secs: #{state.secs}")
    {:reply, state.secs, state}
  end

  @impl true
  def handle_cast(:stop, state) do
    Logger.info("Stopping")
    {:stop, :normal, state}
  end

  @impl true
  def terminate(reason, _state) do
    Logger.info("Stopped #{reason}")
  end

  @impl true
  def handle_info(:yo, state) do
    Logger.info("Got a :yo")
    {:noreply, state}
  end
end
