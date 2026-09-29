defmodule BluOSNowPlaying.Release.NIFsFromERTS do
  @moduledoc """
  Makes the release's NIF shared objects the ones from the ERTS Burrito bundles.

  The ERTS Burrito fetches was built for the *target* platform, so its NIFs are
  the only ones that can run there. The ones `mix release` put in the payload are
  the building machine's, and for a cross build those are simply unusable: a
  Linux binary is statically linked against musl and cannot relocate a NIF from a
  glibc build, and a macOS or Windows payload carries NIFs for the build
  machine's architecture, which the target cannot load.

  Burrito's own `CopyERTS` step installs the bundled NIFs, but it only replaces an
  existing one when the application *version* directories happen to agree, say
  `lib/crypto-5.8.2` over `lib/crypto-5.8.2`. Two builds of the same OTP disagree
  about those versions often enough that it is not a thing to rely on, and when
  they do disagree the bundled copy lands in a directory nothing reads from: a
  NIF is loaded from the application directory the release's boot script lists,
  which is the one the building Erlang created, so the host's copy keeps winning.
  The binary then dies on the first request that touches a session, with
  `Unable to load crypto library` from `plug Plug.Session` and, underneath it,
  `Error relocating ...: symbol not found` for whatever the host's C toolchain
  inlined. The generic "OpenSSL might not be installed" that Burrito prints
  alongside it is a red herring; there is nothing to install.

  This step therefore rewrites the NIFs the release has, in the release's own
  application directory, so that the file a target loads is the bundled ERTS's.
  Only NIFs the ERTS also provides are touched, which leaves a NIF shipped by a
  dependency, or one that only the building Erlang has, alone.
  """

  @behaviour Burrito.Builder.Step

  alias Burrito.Builder.Context
  alias Burrito.Builder.Log

  # What a NIF is called on each platform: `erlang:load_nif/2` appends the
  # extension of the platform it runs on to the path the NIF hands it, so a
  # `.dll` can replace a `.so` in the same directory.
  @shared_objects ~w(.so .dll .dylib)

  @impl Burrito.Builder.Step
  def execute(%Context{} = context) do
    case context.target.erts_source do
      {:local_unpacked, path: erts_location} ->
        report(install_erts_nifs(context.work_dir, erts_location))

      _other ->
        :ok
    end

    context
  end

  @doc """
  Replaces the NIFs in the release at `work_dir` with the ones in `erts_location`.

  NIFs are paired by name rather than by path, because the two trees disagree on
  both the application version (`crypto-5.8.2` against `crypto-5.8.3`) and the
  extension (`.dll` against `.so`) for the very same NIF.

  Returns the NIFs that were replaced and the ones that were left alone, each as
  a map with a `:name` and, for the replaced ones, the `:source`,
  `:destination` and the `:replaced` paths.
  """
  def install_erts_nifs(work_dir, erts_location) do
    bundled = shared_objects(erts_location)
    release = shared_objects(work_dir)

    {replaceable, keep} =
      Enum.split_with(release, fn {name, _paths} -> Map.has_key?(bundled, name) end)

    replaced =
      Enum.map(replaceable, fn {name, paths} ->
        [source | _] = Map.fetch!(bundled, name)
        Enum.each(paths, &File.rm!/1)
        destination = Path.join(Path.dirname(hd(paths)), Path.basename(source))
        File.mkdir_p!(Path.dirname(destination))
        File.cp!(source, destination)

        %{name: name, source: source, destination: destination, replaced: paths}
      end)

    kept = Enum.map(keep, fn {name, paths} -> %{name: name, paths: paths} end)

    {replaced, kept}
  end

  defp shared_objects(root) do
    root
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.filter(&(Path.extname(&1) in @shared_objects))
    |> Enum.group_by(&Path.basename(&1, Path.extname(&1)), & &1)
    |> Map.new(fn {name, paths} -> {name, Enum.sort(paths)} end)
  end

  defp report({replaced, kept}) do
    Enum.each(replaced, fn nif ->
      Log.success(
        :step,
        "Installed NIF #{nif.destination} from the bundled ERTS, replacing #{Enum.join(nif.replaced, ", ")}"
      )
    end)

    if kept != [] do
      Log.warning(
        :step,
        "The bundled ERTS has no #{Enum.map_join(kept, ", ", & &1.name)}, so the release's own NIF stays. " <>
          "It can only load where the two agree on the platform, which a cross build cannot count on."
      )
    end
  end
end
