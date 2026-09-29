defmodule BluOSNowPlaying.Release do
  @moduledoc """
  Release step that wraps the application in a Burrito binary.

  Wrapping is opt-in through the `BURRITO_BUILD` environment variable, because it
  needs Zig, `xz` and `7zz` on the build machine. `mix release` is also the step
  the `Dockerfile` uses, and that image has none of those tools, so there the
  step has to assemble the plain release and stay out of the way. Set
  `BURRITO_BUILD=true`, or run `mix release.burrito`, to get the binaries.

  Burrito resolves the prebuilt ERTS from its own default resolver, so ours is
  registered first to pin the ERTS version (see `BluOSNowPlaying.Release.ERTSResolver`).
  """

  @doc """
  Wraps `release` in a Burrito binary for every configured target.

  Returns `release` untouched when `BURRITO_BUILD` is not set, which leaves a
  working release in `_build/prod/rel/bluos_now_playing`.
  """
  def wrap(%Mix.Release{} = release) do
    if burrito_build?() do
      Burrito.register_erts_resolver(BluOSNowPlaying.Release.ERTSResolver)
      Burrito.wrap(release)
    else
      release
    end
  end

  @doc """
  Whether this build should produce Burrito binaries, from `BURRITO_BUILD`.
  """
  def burrito_build?() do
    System.get_env("BURRITO_BUILD") in ~w(1 true)
  end
end
