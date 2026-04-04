defmodule CadenceWeb.ConnCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint CadenceWeb.Endpoint

      import Plug.Conn
      import Phoenix.ConnTest
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Cadence.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(Cadence.Repo, {:shared, self()})
    end

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
