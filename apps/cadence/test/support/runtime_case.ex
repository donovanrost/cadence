defmodule Cadence.RuntimeCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Cadence.Control.Missions, as: ControlMissions
  alias Cadence.Telemetry.CurrentValueStore
  alias Cadence.Telemetry.CurrentValueStore.ETS

  using opts do
    isolated? = Keyword.get(opts, :isolated, false)

    quote do
      @moduletag :runtime

      if unquote(isolated?) do
        @moduletag runtime_case: :isolated
      end

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

  def setup_owned_runtime(%{runtime_case: :isolated} = tags) do
    pid = Cadence.DataCase.start_sandbox_owner!(tags, shared?: false)

    on_exit(fn ->
      stop_isolated_sandbox_owner(pid)
    end)

    %{sandbox_owner_pid: pid}
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

  defp stop_isolated_sandbox_owner(pid) do
    if Process.alive?(pid) do
      Cadence.DataCase.stop_sandbox_owner(pid)
    end

    :ok
  catch
    :exit, _reason -> :ok
  end
end
