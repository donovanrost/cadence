defmodule CadenceWeb.Plugs.FrontendReleasePublisherSession do
  @moduledoc false

  alias CadenceWeb.Plugs.FrontendReleaseRequestBody

  @spec init(Plug.opts()) :: Plug.opts()
  def init(opts) do
    %{
      plain: Plug.Session.init(opts),
      review: Plug.Session.init(Keyword.put(opts, :secure, true))
    }
  end

  @spec call(Plug.Conn.t(), Plug.opts()) :: Plug.Conn.t()
  def call(%Plug.Conn{} = conn, opts) do
    session_opts =
      if Application.get_env(:cadence_web, :review_session_secure?, false),
        do: opts.review,
        else: opts.plain

    if FrontendReleaseRequestBody.publisher_request?(conn),
      do: conn,
      else: Plug.Session.call(conn, session_opts)
  end
end
