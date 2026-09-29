defmodule BluOSNowPlaying.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BluOSNowPlayingWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:bluos_now_playing, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: BluOSNowPlaying.PubSub},
      {BluOSNowPlaying.Player, name: BluOSNowPlaying.Player, init_arg: :saved},
      # Start a worker by calling: BluOSNowPlaying.Worker.start_link(arg)
      # {BluOSNowPlaying.Worker, arg},
      # Start to serve requests, typically the last entry
      BluOSNowPlayingWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BluOSNowPlaying.Supervisor]
    {:ok, pid} = Supervisor.start_link(children, opts)

    # Burrito's launcher starts the release with `Elixir.CLI.start_cli/0` and
    # without the `--no-halt` the release's own `bin/bluos_now_playing` passes.
    # That halts the VM as soon as every application has finished starting, so
    # a release that just returns here shuts down again right after the
    # endpoint reports that it is up. Parking this process keeps the boot open
    # for as long as the server runs. The release's own start script does pass
    # --no-halt, and every other entry point runs the application normally, so
    # only the standalone binaries park here.
    if System.get_env("__BURRITO") do
      Process.sleep(:infinity)
    end

    {:ok, pid}
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BluOSNowPlayingWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
