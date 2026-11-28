defmodule CadenceWeb.Plugs.Session do
  @moduledoc """
  The browser session cookie. A dev review server behind an HTTPS origin
  (`:review_session_secure?`) marks the cookie secure.
  """

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

    Plug.Session.call(conn, session_opts)
  end
end
