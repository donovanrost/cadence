defmodule Cadence.IntegrationCase do
  @moduledoc """
  Test case for integration tests that require the full app/data-plane.

  This starts the full Cadence application (supervision tree) and uses DataCase.
  Integration tests are excluded by default; run with `mix test --include integration`.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      use Cadence.DataCase, async: false

      @moduletag :integration
    end
  end

  setup_all do
    Application.put_env(:cadence, :integration_mode, true)
    Sandbox.mode(Cadence.Repo, :auto)

    Cadence.TestSupport.start_full_app()
    Sandbox.mode(Cadence.Repo, :manual)

    on_exit(fn ->
      Sandbox.mode(Cadence.Repo, :manual)
      Application.delete_env(:cadence, :integration_mode)
    end)

    :ok
  end
end
