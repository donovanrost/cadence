defmodule CadenceSimulator.DataCase do
  use ExUnit.CaseTemplate

  alias Cadence.Missions.Mission
  alias Cadence.Organizations.Organization

  using do
    quote do
      alias Cadence.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import CadenceSimulator.DataCase
    end
  end

  setup tags do
    {:ok, _started_apps} = Application.ensure_all_started(:cadence)
    pid = start_owner_with_retry!(shared: not tags[:async])

    on_exit(fn ->
      unless tags[:async] do
        Cadence.Runtime.stop_all_missions()
      end

      if telemetry_current_value_store_module() == Cadence.Telemetry.CurrentValueStore.ETS do
        Cadence.Telemetry.CurrentValueStore.reset()
      end

      Ecto.Adapters.SQL.Sandbox.stop_owner(pid)
    end)

    :ok
  end

  defp start_owner_with_retry!(opts, attempts \\ 20)

  defp start_owner_with_retry!(_opts, 0) do
    raise "Cadence.Repo sandbox owner did not start in time"
  end

  defp start_owner_with_retry!(opts, attempts) do
    try do
      Ecto.Adapters.SQL.Sandbox.start_owner!(Cadence.Repo, opts)
    rescue
      MatchError ->
        Process.sleep(50)
        {:ok, _started_apps} = Application.ensure_all_started(:cadence)
        start_owner_with_retry!(opts, attempts - 1)
    catch
      :exit, _reason ->
        Process.sleep(50)
        {:ok, _started_apps} = Application.ensure_all_started(:cadence)
        start_owner_with_retry!(opts, attempts - 1)
    end
  end

  def persist_mission_scope(organization_id, mission_id, opts \\ []) do
    organization =
      Organization.new(%{
        organization_id: organization_id,
        slug: Keyword.get(opts, :organization_slug, organization_id),
        display_name: Keyword.get(opts, :organization_name, organization_id)
      })

    mission =
      Mission.new(%{
        mission_id: mission_id,
        organization_id: organization_id,
        slug: Keyword.get(opts, :mission_slug, mission_id),
        display_name: Keyword.get(opts, :mission_name, mission_id)
      })

    {:ok, persisted_organization} = Cadence.persist_organization(organization)
    {:ok, persisted_mission} = Cadence.persist_mission(mission)

    %{organization: persisted_organization, mission: persisted_mission}
  end

  defp telemetry_current_value_store_module do
    Application.get_env(:cadence, :telemetry_current_value_store, [])
    |> Keyword.get(:module)
  end
end
