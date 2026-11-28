defmodule Cadence.Reads.CatalogSystems do
  @moduledoc """
  The SpaceSystems a catalog revision's mission model has and what each holds (ADR-020 P5, #1078
  slice B1): the choices a spacecraft's binding offers, beside `CatalogApids`. `available: false`
  when the revision has no compiled model yet, so the list is empty, not wrong.

  Each system: `system_id`, `path`, `name`, `parent_id`, its `packets` (`packet_definition_id`,
  `name`, `runtime_name`, `apid`), its `commands` (`command_id`, `name`, `runtime_name`) and the
  counts of its `algorithms` and `policies`.
  """

  alias Cadence.Catalog
  alias Cadence.MissionModels
  alias Cadence.MissionModels.SystemSelection

  @spec load(binary(), binary(), binary()) ::
          {:ok, %{revision_id: binary(), available: boolean(), systems: [map()]}}
          | {:error, :catalog_revision_not_found}
  def load(organization_id, mission_id, catalog_revision_id) do
    with {:ok, catalog} <-
           Catalog.fetch_revision(organization_id, mission_id, catalog_revision_id) do
      case systems(catalog) do
        {:ok, systems} ->
          {:ok, %{revision_id: catalog_revision_id, available: true, systems: systems}}

        :unavailable ->
          {:ok, %{revision_id: catalog_revision_id, available: false, systems: []}}
      end
    end
  end

  @doc """
  The catalog revision's executable telemetry plan, or nil when it names no revision or the
  revision has no compiled model: one catalog row and one plan row (never the revision's
  declarations or the other plans), for a read that wants a craft's effective systems.
  """
  @spec telemetry_plan(binary(), binary(), binary() | nil) :: struct() | nil
  def telemetry_plan(_organization_id, _mission_id, nil), do: nil

  def telemetry_plan(organization_id, mission_id, catalog_revision_id) do
    with {:ok, %{mission_model_revision_id: model_id}} when is_binary(model_id) <-
           Catalog.fetch_revision(organization_id, mission_id, catalog_revision_id),
         {:ok, plan} <-
           MissionModels.fetch_plan(organization_id, mission_id, model_id, :telemetry) do
      plan
    else
      _unavailable -> nil
    end
  end

  @doc """
  The systems a document's `handled_apids` amount to in `plan` (`telemetry_plan/3`): `[%{system_id,
  path, name, bound, apids}]`; nil `handled_apids` is every APID of the plan (all systems, bound
  `:all`), `[]` none. nil when there is no plan.
  """
  @spec effective(struct() | nil, [non_neg_integer()] | nil) :: [map()] | nil
  def effective(nil, _apids), do: nil
  def effective(plan, nil), do: SystemSelection.effective(plan, :all)
  def effective(plan, apids), do: SystemSelection.effective(plan, {:apids, apids})

  defp systems(catalog) do
    case model(catalog) do
      {:ok, revision, plans} -> {:ok, SystemSelection.contributions(revision, plans)}
      :error -> :unavailable
    end
  end

  defp model(%{mission_model_revision_id: model_id} = catalog)
       when is_binary(model_id) and model_id != "" do
    with {:ok, revision} <-
           MissionModels.fetch_revision(catalog.organization_id, catalog.mission_id, model_id),
         {:ok, plans} <-
           MissionModels.fetch_runtime_plans(
             catalog.organization_id,
             catalog.mission_id,
             model_id
           ) do
      {:ok, revision, plans}
    else
      _no_model -> :error
    end
  end

  defp model(_catalog), do: :error
end
