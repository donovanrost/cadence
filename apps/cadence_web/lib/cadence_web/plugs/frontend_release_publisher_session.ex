defmodule CadenceWeb.Plugs.FrontendReleasePublisherSession do
  @moduledoc false

  alias CadenceWeb.Plugs.FrontendReleaseRequestBody

  @spec init(Plug.opts()) :: Plug.opts()
  def init(opts), do: Plug.Session.init(opts)

  @spec call(Plug.Conn.t(), Plug.opts()) :: Plug.Conn.t()
  def call(%Plug.Conn{} = conn, opts) do
    if FrontendReleaseRequestBody.publisher_request?(conn),
      do: conn,
      else: Plug.Session.call(conn, opts)
  end
end
