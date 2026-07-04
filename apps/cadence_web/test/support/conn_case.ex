defmodule CadenceWeb.ConnCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      @endpoint CadenceWeb.Endpoint

      import Plug.Conn
      import Phoenix.ConnTest
      import CadenceWeb.ConnCase
    end
  end

  setup tags do
    owner =
      Sandbox.start_owner!(
        Cadence.Repo,
        sandbox_owner_options(tags)
      )

    on_exit(fn ->
      Sandbox.stop_owner(owner)
    end)

    {:ok, conn: Phoenix.ConnTest.build_conn(), sandbox_owner: owner}
  end

  defp sandbox_owner_options(tags) do
    shared? = not tags[:async]

    [shared: shared?]
    |> maybe_put_ownership_timeout(
      tags[:sandbox_ownership_timeout] || default_ownership_timeout(shared?)
    )
  end

  defp default_ownership_timeout(true), do: 600_000
  defp default_ownership_timeout(false), do: nil

  defp maybe_put_ownership_timeout(options, timeout) when is_integer(timeout) and timeout > 0 do
    Keyword.put(options, :ownership_timeout, timeout)
  end

  defp maybe_put_ownership_timeout(options, _timeout), do: options

  def reset_bootstrap_state! do
    SQL.query!(Cadence.Repo, "TRUNCATE organizations CASCADE", [])
  end
end
