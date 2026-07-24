defmodule Cadence.RuntimeCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Cadence.Control.Missions, as: ControlMissions
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
    stop_all_control_missions()
    Cadence.Runtime.stop_all_missions()

    pid = Cadence.DataCase.start_sandbox_owner!(tags, shared?: true)

    on_exit(fn ->
      stop_all_control_missions()
      Cadence.Runtime.stop_all_missions()

      if Cadence.DataCase.telemetry_current_value_store_module() == ETS do
        CurrentValueStore.reset()
      end

      Cadence.DataCase.stop_sandbox_owner(pid)
      Cadence.DataCase.ensure_cadence_started!()
    end)

    :ok
  end

  defp stop_all_control_missions do
    ControlMissions.running_mission_ids()
    |> Enum.each(&ControlMissions.stop/1)
  end
end
