# BluOSNowPlaying

BluOSNowPlaying interfaces with a BluOS (Bluesound) player
to access the necessary data for a 'now playing' status.

This web application connects to a BluOS player on your network
and offers a page show a now playing screen.

## References

* https://www.bluesound.com
* https://bluos.io
* https://bluesoundprofessional.com
* https://bluesoundprofessional.com/wp-content/uploads/2025/06/BluOS-Custom-Integration-API_v1.7.pdf

The main technical reference is the `BluOS Custom Integration API` version 1.7 which describes
the HTTP REST API to interact with a player as well as the Lenbrook Service Discovery Protocol (LSDP)
to discover players on the network.

## Getting started

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
