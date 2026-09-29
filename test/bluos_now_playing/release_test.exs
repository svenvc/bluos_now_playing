defmodule BluOSNowPlaying.ReleaseTest do
  use ExUnit.Case, async: false

  setup do
    original = System.get_env("BURRITO_BUILD")
    on_exit(fn -> restore(original) end)
    :ok
  end

  defp restore(nil), do: System.delete_env("BURRITO_BUILD")
  defp restore(value), do: System.put_env("BURRITO_BUILD", value)

  describe "burrito_build?/0" do
    test "is off when BURRITO_BUILD is unset, so the Dockerfile gets a plain release" do
      System.delete_env("BURRITO_BUILD")

      refute BluOSNowPlaying.Release.burrito_build?()
    end

    test "is off for the value the Dockerfile sets" do
      System.put_env("BURRITO_BUILD", "false")

      refute BluOSNowPlaying.Release.burrito_build?()
    end

    test "is on for the values mix release.burrito and a shell user set" do
      for value <- ~w(1 true) do
        System.put_env("BURRITO_BUILD", value)

        assert BluOSNowPlaying.Release.burrito_build?()
      end
    end
  end

  describe "wrap/1" do
    test "returns the release untouched without BURRITO_BUILD" do
      System.delete_env("BURRITO_BUILD")
      release = %Mix.Release{name: :bluos_now_playing, version: "0.1.0", path: "/tmp"}

      # Wrapping would shell out to Zig, so a passthrough is the only thing that
      # can happen here, and it is what keeps `mix release` working in Docker.
      assert BluOSNowPlaying.Release.wrap(release) == release
    end
  end
end
