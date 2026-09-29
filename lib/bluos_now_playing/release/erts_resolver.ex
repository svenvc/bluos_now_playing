defmodule BluOSNowPlaying.Release.ERTSResolver do
  @moduledoc """
  Pins the prebuilt ERTS that Burrito bundles into the binaries.

  Burrito asks the BEAM Machine for the ERTS matching the Erlang that is running
  the build, down to the patch level. Two things have to be corrected for that
  request to work and for the result to run:

    * The BEAM Machine publishes no patch-level tarballs, so a request for
      29.1.1 404s while 29.1 resolves. The pin is therefore `X.Y`.

    * The pin has to match the minor version of the Erlang that built the
      payload. Burrito only replaces `erts-*/bin` and the NIF shared objects of
      the ERTS that `mix release` already put in the payload, so the host's own
      ERTS beams stay put. Bundling a different minor loads, say, the OTP 28
      `prim_tty` beam against the OTP 29 NIF, and the kernel dies on
      `bad_lib: Function not found prim_tty:setupterm_nif/0`. A host running
      28.5 therefore gets the 28.5 ERTS.

  The rewrite happens here rather than through Burrito's `:custom_erts` option
  because a target with a custom ERTS no longer counts as precompiled, which
  skips the musl step that Linux binaries need.
  """

  @behaviour Burrito.Util.ERTSResolver

  alias Burrito.Builder.Target

  @doc """
  The prebuilt ERTS release the binaries are bundled with, `X.Y`.

  Reads the version of the Erlang running the build, the same source Burrito
  resolves its default ERTS from, and drops the patch level. Note that
  `System.version/0` is no help here: it reports the Elixir version.
  """
  def erts_version do
    Burrito.Util.get_otp_version()
    |> String.split(".")
    |> Enum.take(2)
    |> Enum.join(".")
  end

  @impl Burrito.Util.ERTSResolver
  def do_resolve(%Target{} = target) do
    target
    |> pin_erts()
    |> Burrito.Util.DefaultERTSResolver.do_resolve()
  end

  @doc """
  Points a precompiled ERTS request at the pinned version.

  Leaves any other ERTS source, such as one set through `:custom_erts`, alone.
  """
  def pin_erts(%Target{erts_source: {:precompiled, _}} = target) do
    %Target{target | erts_source: {:precompiled, version: erts_version()}}
  end

  def pin_erts(%Target{} = target), do: target
end
