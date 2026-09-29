defmodule BluOSNowPlaying.Release.ERTSResolverTest do
  use ExUnit.Case, async: true

  alias Burrito.Builder.Target

  describe "pin_erts/1" do
    test "points a precompiled ERTS request at the pinned version" do
      target = Target.init_target(:linux, os: :linux, cpu: :x86_64)

      assert %Target{erts_source: {:precompiled, version: version}} =
               BluOSNowPlaying.Release.ERTSResolver.pin_erts(target)

      assert version == BluOSNowPlaying.Release.ERTSResolver.erts_version()
    end

    test "leaves a custom ERTS source untouched" do
      # `init_target/2` builds its struct dynamically, so the match tells the
      # compiler this is a `%Target{}` before the update below.
      %Target{} = target = Target.init_target(:linux, os: :linux, cpu: :x86_64)
      custom = %Target{target | erts_source: {:local, path: "/tmp/erts.tar.gz"}}

      assert BluOSNowPlaying.Release.ERTSResolver.pin_erts(custom) == custom
    end
  end

  describe "erts_version/0" do
    test "is a release the BEAM Machine publishes" do
      # The BEAM Machine has no tarballs for patch level ERTS releases, so a
      # version like "29.1.1" makes every build fail on a 404.
      assert BluOSNowPlaying.Release.ERTSResolver.erts_version() =~ ~r/^\d+\.\d+$/
    end

    test "matches the minor version of the Erlang running the build" do
      # Burrito keeps the host's ERTS beams in the payload and only swaps the
      # binaries and NIFs, so bundling another minor leaves, say, an OTP 28
      # prim_tty beam to call an OTP 29 NIF and the kernel stops booting.
      host = Burrito.Util.get_otp_version() |> String.split(".") |> Enum.take(2) |> Enum.join(".")

      assert BluOSNowPlaying.Release.ERTSResolver.erts_version() == host
    end
  end
end
