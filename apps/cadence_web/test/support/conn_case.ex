defmodule CadenceWeb.ConnCase do
  @moduledoc false

  use ExUnit.CaseTemplate

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
    if tags[:runtime] do
      Cadence.RuntimeTestSupport.prepare_default_runtime()
    end

    owner =
      Sandbox.start_owner!(
        Cadence.Repo,
        sandbox_owner_options(tags)
      )

    on_exit(fn ->
      if tags[:runtime] do
        Cadence.RuntimeTestSupport.cleanup_default_runtime()
      end

      Sandbox.stop_owner(owner)

      if tags[:runtime] do
        Cadence.DataCase.ensure_cadence_started!()
      end
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
end
