defmodule Cadence.Control.ModelApprovalGate do
  @moduledoc """
  A generation may introduce a mission-model revision only when it is approved
  (`MissionModels.approve_revision/5`) and its comparison against the revision the moved
  spacecraft ran before has passed (DECISIONS #92 (a), director 11-15, option C: a static
  comparison; replay runs when the mission has qualification cases).

  "Introduced" means run by a spacecraft in the new generation and by none in the active one:
  revisions already running are grandfathered, so a mission whose models predate the gate keeps
  working. Both activation paths check it: the change-set apply (`ConfigurationGeneration`) and
  the per-spacecraft review (`MissionModelPromotion`'s fleet branch). Before this, neither
  checked approval or qualification; only the legacy mission-wide branch did.
  """

  alias Cadence.Activations
  alias Cadence.Catalog
  alias Cadence.Catalog.FleetSnapshot
  alias Cadence.MissionModels
  alias Cadence.MissionModels.Comparison

  @doc """
  The revisions `entries` (spacecraft id => fleet entry) run that `running` (the active
  generation's entries) don't: `%{revision_id => %{spacecraft_ids: [id], baselines: [id | nil]}}`.
  A baseline is the revision that spacecraft ran before.
  """
  @spec introduced(map(), map()) :: map()
  def introduced(entries, running) do
    running_ids = running |> Map.values() |> Enum.map(&revision_id/1) |> MapSet.new()

    entries
    |> Enum.reject(fn {_id, entry} ->
      is_nil(revision_id(entry)) or MapSet.member?(running_ids, revision_id(entry))
    end)
    |> Enum.group_by(fn {_id, entry} -> revision_id(entry) end, &elem(&1, 0))
    |> Map.new(fn {revision, ids} ->
      {revision,
       %{
         spacecraft_ids: Enum.sort(ids),
         baselines:
           ids |> Enum.map(&revision_id(running[&1] || running["__mission__"])) |> Enum.uniq()
       }}
    end)
  end

  @doc """
  The active generation's entries. A legacy (mission-wide) activation counts its one revision as
  `"__mission__"`, the baseline for every spacecraft; with no active generation, `%{}`.
  """
  @spec running_entries(binary(), binary()) :: map()
  def running_entries(organization_id, mission_id) do
    case Activations.fetch_active_activation(organization_id, mission_id) do
      {:ok, %{metadata: metadata}} -> metadata_entries(metadata)
      _none -> %{}
    end
  end

  @doc """
  `:ok`, or why the generation can't introduce its new revisions:
  `{:mission_model_revision_not_approved, [revision_id]}` or
  `{:mission_model_comparison_failed, revision_id, comparison_report_id}`.
  """
  @spec check(binary(), binary(), map(), map(), map()) :: :ok | {:error, term()}
  def check(organization_id, mission_id, entries, running, binding_set) do
    introduced = introduced(entries, running)

    with :ok <- approved(organization_id, mission_id, Map.keys(introduced)) do
      compared(organization_id, mission_id, introduced, binding_set)
    end
  end

  @doc "The ones among `revision_ids` that aren't approved."
  @spec unapproved(binary(), binary(), [binary()]) :: [binary()]
  def unapproved(organization_id, mission_id, revision_ids) do
    statuses = MissionModels.revision_statuses(organization_id, mission_id, revision_ids)
    revision_ids |> Enum.reject(&(statuses[&1] == :approved)) |> Enum.sort()
  end

  @doc """
  For the preview: the target catalogs of `changes` (`%{spacecraft_id => %{to: catalog_id}}`)
  whose mission model the active generation doesn't run and isn't approved:
  `[%{catalog_revision_id, mission_model_revision_id, spacecraft_ids}]`.
  """
  @spec unapproved_targets(binary(), binary(), map()) :: [map()]
  def unapproved_targets(organization_id, mission_id, changes) do
    running =
      organization_id
      |> running_entries(mission_id)
      |> Map.values()
      |> MapSet.new(&revision_id/1)

    targets =
      changes
      |> Enum.group_by(fn {_id, change} -> change.to end, &elem(&1, 0))
      |> Enum.flat_map(fn {catalog_id, ids} ->
        case catalog_id && Catalog.fetch_revision(organization_id, mission_id, catalog_id) do
          {:ok, %{mission_model_revision_id: revision}} when is_binary(revision) ->
            [
              %{
                catalog_revision_id: catalog_id,
                mission_model_revision_id: revision,
                spacecraft_ids: Enum.sort(ids)
              }
            ]

          _none ->
            []
        end
      end)
      |> Enum.reject(&MapSet.member?(running, &1.mission_model_revision_id))

    unapproved =
      MapSet.new(
        unapproved(organization_id, mission_id, Enum.map(targets, & &1.mission_model_revision_id))
      )

    Enum.filter(targets, &MapSet.member?(unapproved, &1.mission_model_revision_id))
  end

  defp approved(organization_id, mission_id, revision_ids) do
    case unapproved(organization_id, mission_id, revision_ids) do
      [] -> :ok
      ids -> {:error, {:mission_model_revision_not_approved, ids}}
    end
  end

  defp compared(organization_id, mission_id, introduced, binding_set) do
    pairs =
      for {revision, %{baselines: baselines}} <- introduced, b <- baselines, do: {revision, b}

    Enum.reduce_while(pairs, :ok, fn {revision, baseline}, :ok ->
      case Comparison.run(
             organization_id,
             mission_id,
             revision,
             binding_set.binding_set_id,
             binding_set.version,
             baseline_revision_id: baseline
           ) do
        {:ok, %{"status" => "passed"}} ->
          {:cont, :ok}

        {:ok, report} ->
          {:halt,
           {:error, {:mission_model_comparison_failed, revision, report["comparison_report_id"]}}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp metadata_entries(metadata) do
    if FleetSnapshot.fleet?(metadata) do
      case FleetSnapshot.entries(metadata) do
        {:ok, entries} -> entries
        _unreadable -> %{}
      end
    else
      case get_in(metadata, ["mission_model", "revision_id"]) do
        id when is_binary(id) -> %{"__mission__" => %{"mission_model" => %{"revision_id" => id}}}
        _none -> %{}
      end
    end
  end

  defp revision_id(%{"mission_model" => %{"revision_id" => id}}) when is_binary(id), do: id
  defp revision_id(_entry), do: nil
end
