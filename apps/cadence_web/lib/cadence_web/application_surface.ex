defmodule CadenceWeb.ApplicationSurface do
  @moduledoc """
  Trusted first-party adapter contract for a host-rendered application surface.

  The stable renderer identifier is resolved by `ApplicationSurfaceRegistry`;
  application definitions do not contain web module names.
  """

  alias Phoenix.LiveView.{Rendered, Socket}

  @callback mount(Socket.t()) :: {:ok, Socket.t()} | {:error, term()}
  @callback handle_event(binary(), map(), Socket.t()) :: {:noreply, Socket.t()}
  @callback handle_info(term(), Socket.t()) :: {:noreply, Socket.t()}
  @callback render(map()) :: Rendered.t()

  @optional_callbacks handle_info: 2
end
