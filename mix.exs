defmodule BluOSNowPlaying.MixProject do
  use Mix.Project

  def project do
    [
      app: :bluos_now_playing,
      version: "0.1.0",
      # Burrito, a build-time dependency below, needs 1.17 or later.
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      releases: releases(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {BluOSNowPlaying.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.1"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.9.0"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.3.0"},
      {:bandit, "~> 1.5"},
      {:req, "~> 0.7.0"},
      {:sweet_xml, "~> 0.7.0"},
      # Build-time only: the release step runs at `mix release` time, so the app
      # never needs Burrito in the payload.
      {:burrito, "~> 1.6", runtime: false}
    ]
  end

  # The release name determines the release directory, the boot script and the
  # binary names, so it stays `bluos_now_playing` for the Docker image and the
  # `rel/overlays/bin/server` script to keep working.
  # BURRITO_TARGET=<alias> mix release builds a single target.
  defp releases do
    [
      bluos_now_playing: [
        steps: [:assemble, &BluOSNowPlaying.Release.wrap/1],
        burrito: [
          # Right after the ERTS is resolved, so it can be read, and before the
          # patch phase copies it in: the NIFs have to be the ERTS's before the
          # payload is assembled, or a cross build ships the build machine's.
          extra_steps: [fetch: [post: [BluOSNowPlaying.Release.NIFsFromERTS]]],
          targets: [
            macos_x86_64: [os: :darwin, cpu: :x86_64],
            macos_arm64: [os: :darwin, cpu: :aarch64],
            linux_x86_64: [os: :linux, cpu: :x86_64],
            linux_arm64: [os: :linux, cpu: :aarch64],
            windows_x86_64: [os: :windows, cpu: :x86_64]
          ]
        ]
      ]
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind bluos_now_playing", "esbuild bluos_now_playing"],
      "assets.deploy": [
        "tailwind bluos_now_playing --minify",
        "esbuild bluos_now_playing --minify",
        "phx.digest"
      ],
      precommit: ["compile --warning-as-errors", "deps.unlock --unused", "format", "test"],
      # Builds the standalone binaries. A function rather than a list of task
      # strings, because it has to set BURRITO_BUILD for the release step.
      # The Mix environment still has to come from the outside:
      #     MIX_ENV=prod mix release.burrito
      # Changing it from in here is too late, loadconfig has already read
      # config/dev.exs by the time an alias runs, and the release then ships an
      # endpoint compiled with the development code reloader.
      "release.burrito": fn _ ->
        unless Mix.env() == :prod do
          Mix.raise("""
          release.burrito builds a production release, run it as:

              MIX_ENV=prod mix release.burrito
          """)
        end

        System.put_env("BURRITO_BUILD", "true")
        # esbuild resolves the phoenix-colocated hooks out of the build path, so
        # the app has to be compiled before the assets are built.
        Mix.Task.run("compile")
        Mix.Task.run("assets.deploy")
        Mix.Task.run("release", ["--overwrite"])
      end
    ]
  end
end
