defmodule Cadence.RuntimeTestSupport do
  @moduledoc false

  alias Cadence.Control.Missions, as: ControlMissions
  alias Cadence.Telemetry.CurrentValueStore
  alias Cadence.Telemetry.CurrentValueStore.ETS

  def prepare_default_runtime do
    Cadence.DataCase.ensure_cadence_started!()
    stop_default_runtime_instances()
  end

  def cleanup_default_runtime do
    stop_default_runtime_instances()

    if Cadence.DataCase.telemetry_current_value_store_module() == ETS do
      CurrentValueStore.reset()
    end

    :ok
  end

  defp stop_default_runtime_instances do
    ControlMissions.running_mission_ids()
    |> Enum.each(&ControlMissions.stop/1)

    Cadence.Runtime.stop_all_missions()
  end
end
