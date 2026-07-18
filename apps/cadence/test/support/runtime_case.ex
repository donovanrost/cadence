defmodule Cadence.RuntimeCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Cadence.Telemetry.CurrentValueStore
  alias Cadence.Telemetry.CurrentValueStore.ETS

  using do
    quote do
      alias Cadence.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Cadence.DataCase
    end
  end

  setup tags do
    Cadence.DataCase.ensure_cadence_started!()
    Cadence.Runtime.stop_all_missions()

    pid = Cadence.DataCase.start_sandbox_owner!(tags, shared?: true)

    on_exit(fn ->
      Cadence.Runtime.stop_all_missions()

      if Cadence.DataCase.telemetry_current_value_store_module() == ETS do
        CurrentValueStore.reset()
      end

      Cadence.DataCase.stop_sandbox_owner(pid)
      Cadence.DataCase.ensure_cadence_started!()
    end)

    :ok
  end
end
