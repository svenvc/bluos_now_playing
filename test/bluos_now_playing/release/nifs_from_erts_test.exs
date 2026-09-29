defmodule BluOSNowPlaying.Release.NIFsFromERTSTest do
  use ExUnit.Case, async: true

  alias BluOSNowPlaying.Release.NIFsFromERTS

  setup do
    tmp = Path.join(System.tmp_dir!(), "nifs_from_erts_#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf!(tmp) end)

    %{tmp: tmp, release: Path.join(tmp, "release"), erts: Path.join(tmp, "erts")}
  end

  # The shape of the two trees that matter: a release carrying the NIFs of the
  # Erlang that built it, and an ERTS built for another platform whose
  # application versions do not match the release's.
  defp write_release(release) do
    write(release, "erts-16.4.0.6/bin/beam.smp", "erts binary")
    write(release, "lib/crypto-5.8.3.3/priv/lib/crypto.so", "host crypto")
    write(release, "lib/crypto-5.8.3.3/priv/lib/crypto_callback.so", "host crypto_callback")
    write(release, "lib/asn1-5.5.2/priv/lib/asn1rt_nif.so", "host asn1")
    write(release, "lib/dep-1.0.0/priv/lib/dep_nif.so", "host dep")
  end

  defp write_erts(erts) do
    write(erts, "otp_x86_64_linux_28.4/erts-16.3/bin/beam.smp", "erts binary")
    write(erts, "otp_x86_64_linux_28.4/lib/crypto-5.8.2/priv/lib/crypto.so", "bundled crypto")
    write(erts, "otp_x86_64_linux_28.4/lib/asn1-5.5.1/priv/lib/asn1rt_nif.so", "bundled asn1")
  end

  defp write(root, path, contents) do
    full = Path.join(root, path)
    File.mkdir_p!(Path.dirname(full))
    File.write!(full, contents)
  end

  describe "install_erts_nifs/2" do
    test "installs the ERTS's NIF where the release's own NIF was", context do
      write_release(context.release)
      write_erts(context.erts)

      {replaced, _kept} = NIFsFromERTS.install_erts_nifs(context.release, context.erts)

      # Not in the ERTS's own crypto-5.8.2 directory: a NIF is loaded from the
      # application directory the boot script lists, which is the one the
      # building Erlang created, and that is what decides the race to load.
      installed =
        Path.join([context.release, "lib", "crypto-5.8.3.3", "priv", "lib", "crypto.so"])

      assert File.read!(installed) == "bundled crypto"
      assert Enum.map(replaced, & &1.name) |> Enum.sort() == ["asn1rt_nif", "crypto"]
    end

    test "replaces a NIF the release has in more than one place", context do
      write_release(context.release)
      write(context.release, "lib/crypto-5.8.3.3/priv/other/crypto.so", "host crypto, elsewhere")
      write_erts(context.erts)

      {replaced, _kept} = NIFsFromERTS.install_erts_nifs(context.release, context.erts)

      crypto = Enum.find(replaced, &(&1.name == "crypto"))

      # Two copies of one NIF is how the same NIF ends up in the payload twice,
      # and only the one in the release's own directory is ever loaded.
      assert length(crypto.replaced) == 2
      assert File.read!(crypto.destination) == "bundled crypto"

      refute File.exists?(
               Path.join([context.release, "lib", "crypto-5.8.3.3", "priv", "other", "crypto.so"])
             )
    end

    test "leaves a NIF the ERTS does not have", context do
      write_release(context.release)
      write_erts(context.erts)

      {_replaced, kept} = NIFsFromERTS.install_erts_nifs(context.release, context.erts)

      # A NIF from a dependency, and one only the building Erlang has, are not
      # the bundled ERTS's to replace. RecompileNIFs owns the first, and there is
      # nothing to put in its place in the second case.
      assert Enum.map(kept, & &1.name) |> Enum.sort() == ["crypto_callback", "dep_nif"]

      untouched =
        Path.join([context.release, "lib", "crypto-5.8.3.3", "priv", "lib", "crypto_callback.so"])

      assert File.read!(untouched) == "host crypto_callback"
    end

    test "names the installed NIF as the ERTS names it", context do
      write(context.release, "lib/crypto-5.8.3.3/priv/lib/crypto.so", "host crypto")
      write(context.erts, "otp_win64_28.4/lib/crypto-5.8.2/priv/lib/crypto.dll", "bundled crypto")

      {replaced, _kept} = NIFsFromERTS.install_erts_nifs(context.release, context.erts)

      [crypto] = replaced

      # erlang:load_nif/2 appends the extension of the platform it runs on, so a
      # Windows target looks for crypto.dll where the release has a crypto.so.
      assert Path.basename(crypto.destination) == "crypto.dll"
      assert File.read!(crypto.destination) == "bundled crypto"

      refute File.exists?(
               Path.join([context.release, "lib", "crypto-5.8.3.3", "priv", "lib", "crypto.so"])
             )
    end

    test "is idempotent", context do
      write_release(context.release)
      write_erts(context.erts)

      NIFsFromERTS.install_erts_nifs(context.release, context.erts)
      {replaced, _kept} = NIFsFromERTS.install_erts_nifs(context.release, context.erts)

      assert Enum.map(replaced, & &1.name) |> Enum.sort() == ["asn1rt_nif", "crypto"]

      installed =
        Path.join([context.release, "lib", "crypto-5.8.3.3", "priv", "lib", "crypto.so"])

      assert File.read!(installed) == "bundled crypto"
    end

    test "leaves a release without NIFs alone", context do
      File.mkdir_p!(context.release)
      File.mkdir_p!(context.erts)
      write_erts(context.erts)

      assert NIFsFromERTS.install_erts_nifs(context.release, context.erts) == {[], []}
    end
  end

  describe "execute/1" do
    test "rewrites the work directory of a resolved ERTS", context do
      write_release(context.release)
      write_erts(context.erts)

      burrito_context = burrito_context(context.release, {:local_unpacked, path: context.erts})

      assert %Burrito.Builder.Context{work_dir: work_dir} = NIFsFromERTS.execute(burrito_context)
      assert work_dir == context.release

      installed =
        Path.join([context.release, "lib", "crypto-5.8.3.3", "priv", "lib", "crypto.so"])

      assert File.read!(installed) == "bundled crypto"
    end

    test "does nothing when the ERTS is the one running the build", context do
      # Burrito makes no copy of a runtime ERTS, so there is nothing to take a
      # NIF from and the host's own is what the binary will load.
      write_release(context.release)

      burrito_context = burrito_context(context.release, {:runtime, version: "28.4.1"})

      assert %Burrito.Builder.Context{} = NIFsFromERTS.execute(burrito_context)

      installed =
        Path.join([context.release, "lib", "crypto-5.8.3.3", "priv", "lib", "crypto.so"])

      assert File.read!(installed) == "host crypto"
    end
  end

  defp burrito_context(work_dir, erts_source) do
    target = %Burrito.Builder.Target{
      alias: :linux_x86_64,
      os: :linux,
      cpu: :x86_64,
      erts_source: erts_source,
      qualifiers: [],
      debug?: false,
      cross_build: true
    }

    %Burrito.Builder.Context{
      target: target,
      mix_release: nil,
      work_dir: work_dir,
      self_dir: "",
      extra_build_env: [],
      halted: false
    }
  end
end
