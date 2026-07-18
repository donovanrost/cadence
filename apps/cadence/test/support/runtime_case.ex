defmodule Cadence.RuntimeCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Cadence.Telemetry.CurrentValueStore
  alias Cadence.Telemetry.CurrentValueStore.ETS

  using do
    quote do
      @moduletag :runtime

      alias Cadence.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Cadence.DataCase
    end
  end

  setup tags do
    setup_owned_runtime(tags)
  end

  def setup_owned_runtime(tags) do
    Cadence.DataCase.ensure_cadence_started!()
    initial_mission_ids = MapSet.new(Cadence.Runtime.running_mission_ids())

    pid = Cadence.DataCase.start_sandbox_owner!(tags, shared?: true)

    on_exit(fn ->
      stop_owned_missions(initial_mission_ids)

      if Cadence.DataCase.telemetry_current_value_store_module() == ETS do
        CurrentValueStore.reset()
      end

      Cadence.DataCase.stop_sandbox_owner(pid)
      Cadence.DataCase.ensure_cadence_started!()
    end)

    :ok
  end

  defp stop_owned_missions(initial_mission_ids) do
    Cadence.Runtime.running_mission_ids()
    |> MapSet.new()
    |> MapSet.difference(initial_mission_ids)
    |> Enum.each(&Cadence.Runtime.stop_mission/1)
  end
end
