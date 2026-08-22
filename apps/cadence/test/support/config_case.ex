defmodule Cadence.ConfigCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      @moduletag :config

      alias Cadence.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Cadence.DataCase
    end
  end

  setup tags do
    if tags[:runtime] do
      Cadence.RuntimeCase.setup_owned_runtime(tags)
    else
      setup_owned_config(tags)
    end
  end

  defp setup_owned_config(tags) do
    Cadence.DataCase.ensure_cadence_started!()

    pid = Cadence.DataCase.start_sandbox_owner!(tags, shared?: true)

    on_exit(fn ->
      Cadence.DataCase.stop_sandbox_owner(pid)
      Cadence.DataCase.ensure_cadence_started!()
    end)

    :ok
  end
end
