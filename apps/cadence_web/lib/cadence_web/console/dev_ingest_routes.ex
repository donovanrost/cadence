defmodule CadenceWeb.Console.DevIngestRoutes do
  @moduledoc """
  Mounts the development ingest routes (#780, #747), and only when `enabled?` is true at compile
  time.

  The router passes `Application.compile_env(:cadence_web, :dev_ingest_routes, false)`; dev and
  test config set it, prod config never does, so the routes are compiled out of a prod release.
  A test builds a router with `mount(false)` and finds no such route in it.
  """

  defmacro mount(enabled?) do
    quote do
      if unquote(enabled?) do
        Phoenix.Router.post("/dev/space_packets", DevIngestController, :space_packet)
        Phoenix.Router.post("/dev/tm_frames", DevIngestController, :tm_frame)
      end
    end
  end
end
