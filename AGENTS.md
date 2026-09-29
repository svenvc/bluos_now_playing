This is a web application written using the Phoenix web framework.

## Project guidelines

- Use `mix precommit` alias when you are done with all changes and fix any pending issues
- Use the already included and available `:req` (`Req`) library for HTTP requests, **avoid** `:httpoison`, `:tesla`, and `:httpc`. Req is included by default and is the preferred HTTP client for Phoenix apps
- Tests for library modules under `lib/bluos_now_playing/` go in `test/bluos_now_playing/` mirroring the module file name (e.g. `test/bluos_now_playing/utils_test.exs`) using plain `ExUnit.Case, async: true`. Web tests stay under `test/bluos_now_playing_web/`. Run the targeted file (`mix test test/bluos_now_playing/utils_test.exs`) before the full `mix precommit`.
- Binary protocol parsers (e.g. LSDP) must be tested against known wire-format packet captures kept as raw binary fixtures, in addition to synthetic packets built with the module's framing helpers — otherwise builder and parser can silently share the same wrong interpretation.
- The stock Phoenix auth guidance in the usage-rules block below (`live_session`, `current_scope`, authenticated routes) is boilerplate and does **not** apply to this app: it has no authentication and no `live_session` blocks

## Standalone binaries (Burrito)

`mix release.burrito` packages the release as self-extracting binaries, one per target, in `burrito_out/`:

```sh
MIX_ENV=prod mix release.burrito                              # all five targets
MIX_ENV=prod BURRITO_TARGET=macos_arm64 mix release.burrito  # one target
MIX_ENV=prod mix release --overwrite                         # plain release, as the Dockerfile does
chmod +x burrito_out/*
./test/smoke.sh burrito_out/bluos_now_playing_macos_arm64  # black-box check against a built binary
```

A binary only runs on the platform it was built for, so `test/smoke.sh` has to be pointed at the one matching the host — it prints the `host target` it expects and says so when handed another platform's binary. The `chmod +x` is needed because Burrito writes the executable bit for the owner only.

Needs Zig **0.16.0** exactly (Burrito hard-fails on any other version), `xz`, and `7zz` for the Windows target. Downloaded ERTS archives are cached in `~/.cache/burrito_file_cache` (macOS: `~/Library/Caches/burrito_file_cache`).

Things that are easy to get wrong here:

- **`MIX_ENV=prod` has to come from the environment**, not from `Mix.env/1` inside the alias. By the time an alias runs, `loadconfig` has already read `config/dev.exs`, and the release then ships an endpoint compiled with the development code reloader. The boot aborts with a `compile_env` error for `[:code_reloader]`. The alias raises with the right command when the env is wrong.
- **Clear the payload cache after every rebuild.** Burrito unpacks into `~/Library/Application Support/.burrito/<app>_erts-X.Y_<version>` and keys that directory on the ERTS and app version only, not on the build. A rebuilt binary at the same version silently runs the *previous* payload — which looks exactly like your changes having no effect. `./burrito_out/bluos_now_playing_macos_arm64 maintenance uninstall` clears it. The key is not per target either, so don't run two architectures of the same version on one machine. `maintenance meta` is the way to confirm which build you are actually on: it reads the metadata embedded in the binary (app name, app version, ERTS version, Zig target, Zig version) without unpacking, so it is also the smoke test's pre-flight, since a binary built for another platform cannot be exec'd at all and therefore cannot answer it. Note that its `erts_version` is the ERTS of the machine that ran `mix release` (`Burrito.Steps.Build.PackAndBuild` reads it off the `Mix.Release`), **not** the ERTS Burrito bundles, so it identifies the build toolchain rather than the runtime inside.
- **Assets must be digested first.** `release.burrito` runs `compile` and `assets.deploy` before `release`, because esbuild resolves the phoenix-colocated hooks out of the build path, and `config/prod.exs` points `cache_static_manifest` at `priv/static/cache_manifest.json`. Without them the page renders unstyled and `test/smoke.sh` fails on the asset checks.
- **The Dockerfile opts out** with `BURRITO_BUILD=false`, so `RUN mix release` there keeps producing a plain release. The wrap step in `releases.steps` is otherwise unconditional and would hard-fail on the missing Zig. The gate lives in `BluOSNowPlaying.Release.burrito_build?/0`.
- **`SECRET_KEY_BASE` and `PHX_SERVER` are optional in a binary.** `config/runtime.exs` falls back to a constant 64-byte secret and to `PHX_HOST=localhost`, and `__BURRITO` (set by the launcher) enables `server: true`, so the binary is a zero-config server. The fallback secret is safe here only because the app has no auth.
- **The app parks in `Application.start/2` under `__BURRITO`.** Burrito starts the release with `Elixir.CLI.start_cli/0` and *without* the `--no-halt` that the release's own `bin/bluos_now_playing` passes, so the VM halts the moment boot completes. A release that just returns from `start/2` exits right after the endpoint reports it is up. Do not "clean this up" by returning `{:ok, pid}`.
- **The launcher does not forward signals** to the BEAM child, so `kill <launcher-pid>` leaves the server running; kill the child (or use Ctrl-C, which hits the whole process group). `test/smoke.sh` kills the child first and lets the launcher exit on its own.
- **CI builds with a fixed Elixir 1.19 / Erlang 28** (`.github/workflows/burrito-build.yml`), which is not the same as a local toolchain. Because the bundled ERTS is pinned from the Erlang version, a released binary therefore carries ERTS 28 while a locally built one carries whatever Erlang you built with. The "Check the ERTS pin" step prints the Erlang in use and its `crypto` application version, which is the pair that decides whether the payload's NIFs are usable; compare minor versions only, because Burrito keeps the host's ERTS beams and swaps the binaries, so another minor is what breaks. The test job in `ci.yaml` deliberately keeps using `erlef/setup-beam` too — tests do not end up in a binary.
- **A binary's NIFs have to come from the ERTS Burrito bundles, not from the Erlang that built them.** This is the subtlest thing here and it cost two CI runs. Burrito downloads a prebuilt ERTS from the BEAM Machine and installs its NIFs, but it only replaces an existing one where the *application version directory* already matches (`deps/burrito/lib/steps/patch/copy_erts.ex` globs `*.{so,dll}` inside the tarball's own `lib/crypto-X.Y.Z`), while `Burrito.Steps.Fetch.Init` deletes only `erts-*` and `releases/*.*.*` directories that are not the build's own. Two builds of the same OTP disagree about those version numbers often enough that it is not a thing to rely on — the toolcache had `crypto-5.8.3.3`, the BEAM Machine publishes `crypto-5.8.2` — and when they do, the bundled copy lands in a directory **nothing reads from**: a NIF is loaded from the application directory the release's boot script lists, which is the one the building Erlang created, so the host's copy keeps winning. For Linux that host NIF is fatal, because the binaries are statically linked against musl while the toolcache's Erlang NIFs are glibc builds with `_FORTIFY_SOURCE`, and the release then dies on the first request that touches the session with `Unable to load crypto library` and, underneath it, `Error relocating ...: symbol not found`. The "OpenSSL might not be installed on this system" line Burrito prints alongside is a red herring; nothing needs installing. `RecompileNIFs` cannot help either, it only covers project dependencies and never crypto. The same broken NIF sits in a `wc` binary without anyone noticing, because a CLI never calls `:crypto`; it is this app's `plug Plug.Session` that first loads it. `BluOSNowPlaying.Release.NIFsFromERTS` is the fix: it runs as a Burrito `extra_steps` hook right after the ERTS is resolved and rewrites the NIFs the release has, in the release's own application directory, so the file a target loads is the bundled ERTS's. Pairing is by NIF *name* rather than path, because the two trees disagree on the version and the extension (`.dll` against `.so`) for the very same NIF, and only the names the ERTS also provides are touched, so a dependency's NIF is left to `RecompileNIFs`.
- **There is no supported way to get a glibc Linux binary out of Burrito.** `Burrito.Util.ERTSUniversalMachineFetcher.fetch_version/4` takes a `libc` argument and ignores it, and `Target.make_triplet/1` tests `qualifiers[:os]`, which `Target.init_target/2` has already split off into fields, so the triplet never gets the `-musl` suffix from there either. The musl runtime comes from `Burrito.Steps.Fetch.Musl`, which only runs for a `{:precompiled, _}` ERTS. A custom ERTS via `:custom_erts` would therefore be a `{:url, _}` target, skipping the musl step, which is why the ERTS version is pinned through a resolver instead.
- **The BEAM Machine publishes the ERTS, not an installable Erlang.** The tarballs it serves are the ERTS payload Burrito needs — `erts-*/bin`, `lib/`, `releases/` — with no `bin/erl` or `bin/elixirc`, so CI cannot use one as a toolchain in place of the toolcache's. It is the thing the binary bundles, nothing more.
- **A socket bound to the IPv6 wildcard is IPv6-only on Windows, and gen_tcp cannot fix that.** `config/runtime.exs` binds `ip: {0,0,0,0,0,0,0,0}` with a comment copied from the Phoenix generator, and on macOS and Linux that socket is dual stack, so it takes IPv4 connections as IPv4 mapped addresses. Windows does not, and a Windows binary came up serving perfectly on `[::1]` while refusing every connection to `127.0.0.1` — a failure that looks like nothing is listening at all, since `netstat` shows only `[::]:port` and the smoke test's IPv4 probe gets a connection refused. The obvious fix, `thousand_island_options: [transport_options: [ipv6_v6only: false]]`, does not work: `gen_tcp` applies that with `setsockopt` *after* the bind, and Windows refuses `IPV6_V6ONLY` on a bound socket, so the listener dies with `:einval` and the app does not start at all. So `runtime.exs` picks the bind address from `:os.type()` and binds `{0,0,0,0}` on Windows, which costs IPv6 there and nothing anywhere else. A Windows binary is IPv4 only until something can set that option before the bind.
- **`test/smoke.sh` reports what the machine can see, and does it while it waits.** An endpoint that never opens is indistinguishable from a slow boot in the log, because the Player polls every ten seconds either way, so the script asks `netstat`, probes the default port and `[::1]`, and prints a raw `curl -v` with the environment's proxy settings left in, and it does that at the first thirty second mark rather than at the end, so a run that gets cancelled still says why. Every curl in the checks passes `--noproxy "*"`, because a request to loopback should never be handed to whatever proxy the environment names.
- **A `code=$(curl ...)` assignment is a `set -e` landmine.** When curl cannot connect it returns non-zero and the script ends right there, which is how one dead-server failure produced a single FAIL line and none of the log that would explain it. Every curl assignment in `test/smoke.sh` ends in `|| code=000` for that reason.
- The macOS binaries ship unsigned, like `expert-lsp` and `wc`: only browser downloads set the `com.apple.quarantine` attribute that Gatekeeper blocks; `curl` installs and tool-based fetches are unaffected. Notarizing with an Apple Developer ID would be the only further step.

### Phoenix v1.8 guidelines

- **Always** begin your LiveView templates with `<Layouts.app flash={@flash} ...>` which wraps all inner content
- The `MyAppWeb.Layouts` module is aliased in the `my_app_web.ex` file, so you can use it without needing to alias it again
- Anytime you run into errors with no `current_scope` assign:
  - You failed to follow the Authenticated Routes guidelines, or you failed to pass `current_scope` to `<Layouts.app>`
  - **Always** fix the `current_scope` error by moving your routes to the proper `live_session` and ensure you pass `current_scope` as needed
- Phoenix v1.8 moved the `<.flash_group>` component to the `Layouts` module. You are **forbidden** from calling `<.flash_group>` outside of the `layouts.ex` module
- Out of the box, `core_components.ex` imports an `<.icon name="hero-x-mark" class="w-5 h-5"/>` component for for hero icons. **Always** use the `<.icon>` component for icons, **never** use `Heroicons` modules or similar
- **Always** use the imported `<.input>` component for form inputs from `core_components.ex` when available. `<.input>` is imported and using it will will save steps and prevent errors
- If you override the default input classes (`<.input class="myclass px-2 py-1 rounded-lg">)`) class with your own values, no default classes are inherited, so your
custom classes must fully style the input

### JS and CSS guidelines

- **Use Tailwind CSS classes and custom CSS rules** to create polished, responsive, and visually stunning interfaces.
- Tailwindcss v4 **no longer needs a tailwind.config.js** and uses a new import syntax in `app.css`:

      @import "tailwindcss" source(none);
      @source "../css";
      @source "../js";
      @source "../../lib/my_app_web";

- **Always use and maintain this import syntax** in the app.css file for projects generated with `phx.new`
- **Never** use `@apply` when writing raw css
- **Always** manually write your own tailwind-based components instead of using daisyUI for a unique, world-class design
- Out of the box **only the app.js and app.css bundles are supported**
  - You cannot reference an external vendor'd script `src` or link `href` in the layouts
  - You must import the vendor deps into app.js and app.css to use them
  - **Never write inline <script>custom js</script> tags within templates**

### UI/UX & design guidelines

- **Produce world-class UI designs** with a focus on usability, aesthetics, and modern design principles
- Implement **subtle micro-interactions** (e.g., button hover effects, and smooth transitions)
- Ensure **clean typography, spacing, and layout balance** for a refined, premium look
- Focus on **delightful details** like hover effects, loading states, and smooth page transitions

## Application architecture

- `BluOSNowPlaying.Player` is the named GenServer owning all player state. It broadcasts `{:update_status, <status>}` on `BluOSNowPlaying.PubSub`, topic `"player"`. The Now Playing LiveView and the `/api/player-status-updates` SSE endpoint subscribe to that topic.
- The Now Playing LiveView renders a standalone full-screen template without `<Layouts.app>`, deliberately deviating from the stock `<Layouts.app>`/`flash_group` boilerplate (unused scaffolding here). Do not wrap it.
- Relative artwork URLs returned by the player must be proxied: call `BluOSNowPlayingWeb.ImageProxy.set_player_host_port(Player.host_port())` so `/proxy-img` can resolve them (the LiveView mount already does this).
- Players are discovered via LSDP UDP broadcasts, or forced with the `BLUOS_PLAYER_IP` env var; the discovered/set core state persists to `.bluos_now_playing.json`.

<!-- usage-rules-start -->

<!-- phoenix:elixir-start -->
## Elixir guidelines

- Elixir lists **do not support index based access via the access syntax**

  **Never do this (invalid)**:

      i = 0
      mylist = ["blue", "green"]
      mylist[i]

  Instead, **always** use `Enum.at`, pattern matching, or `List` for index based list access, ie:

      i = 0
      mylist = ["blue", "green"]
      Enum.at(mylist, i)

- Elixir variables are immutable, but can be rebound, so for block expressions like `if`, `case`, `cond`, etc
  you *must* bind the result of the expression to a variable if you want to use it and you CANNOT rebind the result inside the expression, ie:

      # INVALID: we are rebinding inside the `if` and the result never gets assigned
      if connected?(socket) do
        socket = assign(socket, :val, val)
      end

      # VALID: we rebind the result of the `if` to a new variable
      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end

- **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors
- **Never** use map access syntax (`changeset[:field]`) on structs as they do not implement the Access behaviour by default. For regular structs, you **must** access the fields directly, such as `my_struct.field` or use higher level APIs that are available on the struct if they exist, `Ecto.Changeset.get_field/2` for changesets
- Elixir's standard library has everything necessary for date and time manipulation. Familiarize yourself with the common `Time`, `Date`, `DateTime`, and `Calendar` interfaces by accessing their documentation as necessary. **Never** install additional dependencies unless asked or for date/time parsing (which you can use the `date_time_parser` package)
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards
- Elixir's builtin OTP primitives like `DynamicSupervisor` and `Registry`, require names in the child spec, such as `{DynamicSupervisor, name: MyApp.MyDynamicSup}`, then you can use `DynamicSupervisor.start_child(MyApp.MyDynamicSup, child_spec)`
- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. The majority of times you will want to pass `timeout: :infinity` as option

## Mix guidelines

- Read the docs and options before using tasks (by using `mix help task_name`)
- To debug test failures, run tests in a specific file with `mix test test/my_test.exs` or run all previously failed tests with `mix test --failed`
- `mix deps.clean --all` is **almost never needed**. **Avoid** using it unless you have good reason
<!-- phoenix:elixir-end -->

<!-- phoenix:phoenix-start -->
## Phoenix guidelines

- Remember Phoenix router `scope` blocks include an optional alias which is prefixed for all routes within the scope. **Always** be mindful of this when creating routes within a scope to avoid duplicate module prefixes.

- You **never** need to create your own `alias` for route definitions! The `scope` provides the alias, ie:

      scope "/admin", AppWeb.Admin do
        pipe_through :browser

        live "/users", UserLive, :index
      end

  the UserLive route would point to the `AppWeb.Admin.UserLive` module

- `Phoenix.View` no longer is needed or included with Phoenix, don't use it
<!-- phoenix:phoenix-end -->

<!-- phoenix:html-start -->
## Phoenix HTML guidelines

- Phoenix templates **always** use `~H` or .html.heex files (known as HEEx), **never** use `~E`
- **Always** use the imported `Phoenix.Component.form/1` and `Phoenix.Component.inputs_for/1` function to build forms. **Never** use `Phoenix.HTML.form_for` or `Phoenix.HTML.inputs_for` as they are outdated
- When building forms **always** use the already imported `Phoenix.Component.to_form/2` (`assign(socket, form: to_form(...))` and `<.form for={@form} id="msg-form">`), then access those forms in the template via `@form[:field]`
- **Always** add unique DOM IDs to key elements (like forms, buttons, etc) when writing templates, these IDs can later be used in tests (`<.form for={@form} id="product-form">`)
- For "app wide" template imports, you can import/alias into the `my_app_web.ex`'s `html_helpers` block, so they will be available to all LiveViews, LiveComponent's, and all modules that do `use MyAppWeb, :html` (replace "my_app" by the actual app name)

- Elixir supports `if/else` but **does NOT support `if/else if` or `if/elsif`. **Never use `else if` or `elseif` in Elixir**, **always** use `cond` or `case` for multiple conditionals.

  **Never do this (invalid)**:

      <%= if condition do %>
        ...
      <% else if other_condition %>
        ...
      <% end %>

  Instead **always** do this:

      <%= cond do %>
        <% condition -> %>
          ...
        <% condition2 -> %>
          ...
        <% true -> %>
          ...
      <% end %>

- HEEx require special tag annotation if you want to insert literal curly's like `{` or `}`. If you want to show a textual code snippet on the page in a `<pre>` or `<code>` block you *must* annotate the parent tag with `phx-no-curly-interpolation`:

      <code phx-no-curly-interpolation>
        let obj = {key: "val"}
      </code>

  Within `phx-no-curly-interpolation` annotated tags, you can use `{` and `}` without escaping them, and dynamic Elixir expressions can still be used with `<%= ... %>` syntax

- HEEx class attrs support lists, but you must **always** use list `[...]` syntax. You can use the class list syntax to conditionally add classes, **always do this for multiple class values**:

      <a class={[
        "px-2 text-white",
        @some_flag && "py-5",
        if(@other_condition, do: "border-red-500", else: "border-blue-100"),
        ...
      ]}>Text</a>

  and **always** wrap `if`'s inside `{...}` expressions with parens, like done above (`if(@other_condition, do: "...", else: "...")`)

  and **never** do this, since it's invalid (note the missing `[` and `]`):

      <a class={
        "px-2 text-white",
        @some_flag && "py-5"
      }> ...
      => Raises compile syntax error on invalid HEEx attr syntax

- **Never** use `<% Enum.each %>` or non-for comprehensions for generating template content, instead **always** use `<%= for item <- @collection do %>`
- HEEx HTML comments use `<%!-- comment --%>`. **Always** use the HEEx HTML comment syntax for template comments (`<%!-- comment --%>`)
- HEEx allows interpolation via `{...}` and `<%= ... %>`, but the `<%= %>` **only** works within tag bodies. **Always** use the `{...}` syntax for interpolation within tag attributes, and for interpolation of values within tag bodies. **Always** interpolate block constructs (if, cond, case, for) within tag bodies using `<%= ... %>`.

  **Always** do this:

      <div id={@id}>
        {@my_assign}
        <%= if @some_block_condition do %>
          {@another_assign}
        <% end %>
      </div>

  and **Never** do this – the program will terminate with a syntax error:

      <%!-- THIS IS INVALID NEVER EVER DO THIS --%>
      <div id="<%= @invalid_interpolation %>">
        {if @invalid_block_construct do}
        {end}
      </div>
<!-- phoenix:html-end -->

<!-- phoenix:liveview-start -->
## Phoenix LiveView guidelines

- **Never** use the deprecated `live_redirect` and `live_patch` functions, instead **always** use the `<.link navigate={href}>` and  `<.link patch={href}>` in templates, and `push_navigate` and `push_patch` functions LiveViews
- **Avoid LiveComponent's** unless you have a strong, specific need for them
- LiveViews should be named like `AppWeb.WeatherLive`, with a `Live` suffix. When you go to add LiveView routes to the router, the default `:browser` scope is **already aliased** with the `AppWeb` module, so you can just do `live "/weather", WeatherLive`
- Remember anytime you use `phx-hook="MyHook"` and that js hook manages its own DOM, you **must** also set the `phx-update="ignore"` attribute
- **Never** write embedded `<script>` tags in HEEx. Instead always write your scripts and hooks in the `assets/js` directory and integrate them with the `assets/js/app.js` file

### LiveView streams

- **Always** use LiveView streams for collections for assigning regular lists to avoid memory ballooning and runtime termination with the following operations:
  - basic append of N items - `stream(socket, :messages, [new_msg])`
  - resetting stream with new items - `stream(socket, :messages, [new_msg], reset: true)` (e.g. for filtering items)
  - prepend to stream - `stream(socket, :messages, [new_msg], at: -1)`
  - deleting items - `stream_delete(socket, :messages, msg)`

- When using the `stream/3` interfaces in the LiveView, the LiveView template must 1) always set `phx-update="stream"` on the parent element, with a DOM id on the parent element like `id="messages"` and 2) consume the `@streams.stream_name` collection and use the id as the DOM id for each child. For a call like `stream(socket, :messages, [new_msg])` in the LiveView, the template would be:

      <div id="messages" phx-update="stream">
        <div :for={{id, msg} <- @streams.messages} id={id}>
          {msg.text}
        </div>
      </div>

- LiveView streams are *not* enumerable, so you cannot use `Enum.filter/2` or `Enum.reject/2` on them. Instead, if you want to filter, prune, or refresh a list of items on the UI, you **must refetch the data and re-stream the entire stream collection, passing reset: true**:

      def handle_event("filter", %{"filter" => filter}, socket) do
        # re-fetch the messages based on the filter
        messages = list_messages(filter)

        {:noreply,
        socket
        |> assign(:messages_empty?, messages == [])
        # reset the stream with the new messages
        |> stream(:messages, messages, reset: true)}
      end

- LiveView streams *do not support counting or empty states*. If you need to display a count, you must track it using a separate assign. For empty states, you can use Tailwind classes:

      <div id="tasks" phx-update="stream">
        <div class="hidden only:block">No tasks yet</div>
        <div :for={{id, task} <- @stream.tasks} id={id}>
          {task.name}
        </div>
      </div>

  The above only works if the empty state is the only HTML block alongside the stream for-comprehension.

- **Never** use the deprecated `phx-update="append"` or `phx-update="prepend"` for collections

### LiveView tests

- `Phoenix.LiveViewTest` module and `LazyHTML` (included) for making your assertions
- Form tests are driven by `Phoenix.LiveViewTest`'s `render_submit/2` and `render_change/2` functions
- Come up with a step-by-step test plan that splits major test cases into small, isolated files. You may start with simpler tests that verify content exists, gradually add interaction tests
- **Always reference the key element IDs you added in the LiveView templates in your tests** for `Phoenix.LiveViewTest` functions like `element/2`, `has_element/2`, selectors, etc
- **Never** tests again raw HTML, **always** use `element/2`, `has_element/2`, and similar: `assert has_element?(view, "#my-form")`
- Instead of relying on testing text content, which can change, favor testing for the presence of key elements
- Focus on testing outcomes rather than implementation details
- Be aware that `Phoenix.Component` functions like `<.form>` might produce different HTML than expected. Test against the output HTML structure, not your mental model of what you expect it to be
- When facing test failures with element selectors, add debug statements to print the actual HTML, but use `LazyHTML` selectors to limit the output, ie:

      html = render(view)
      document = LazyHTML.from_fragment(html)
      matches = LazyHTML.filter(document, "your-complex-selector")
      IO.inspect(matches, label: "Matches")

### Form handling

#### Creating a form from params

If you want to create a form based on `handle_event` params:

    def handle_event("submitted", params, socket) do
      {:noreply, assign(socket, form: to_form(params))}
    end

When you pass a map to `to_form/1`, it assumes said map contains the form params, which are expected to have string keys.

You can also specify a name to nest the params:

    def handle_event("submitted", %{"user" => user_params}, socket) do
      {:noreply, assign(socket, form: to_form(user_params, as: :user))}
    end

#### Creating a form from changesets

When using changesets, the underlying data, form params, and errors are retrieved from it. The `:as` option is automatically computed too. E.g. if you have a user schema:

    defmodule MyApp.Users.User do
      use Ecto.Schema
      ...
    end

And then you create a changeset that you pass to `to_form`:

    %MyApp.Users.User{}
    |> Ecto.Changeset.change()
    |> to_form()

Once the form is submitted, the params will be available under `%{"user" => user_params}`.

In the template, the form form assign can be passed to the `<.form>` function component:

    <.form for={@form} id="todo-form" phx-change="validate" phx-submit="save">
      <.input field={@form[:field]} type="text" />
    </.form>

Always give the form an explicit, unique DOM ID, like `id="todo-form"`.

#### Avoiding form errors

**Always** use a form assigned via `to_form/2` in the LiveView, and the `<.input>` component in the template. In the template **always access forms this**:

    <%!-- ALWAYS do this (valid) --%>
    <.form for={@form} id="my-form">
      <.input field={@form[:field]} type="text" />
    </.form>

And **never** do this:

    <%!-- NEVER do this (invalid) --%>
    <.form for={@changeset} id="my-form">
      <.input field={@changeset[:field]} type="text" />
    </.form>

- You are FORBIDDEN from accessing the changeset in the template as it will cause errors
- **Never** use `<.form let={f} ...>` in the template, instead **always use `<.form for={@form} ...>`**, then drive all form references from the form assign as in `@form[:field]`. The UI should **always** be driven by a `to_form/2` assigned in the LiveView module that is derived from a changeset
<!-- phoenix:liveview-end -->

<!-- usage-rules-end -->