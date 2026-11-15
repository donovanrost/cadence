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
  What `entries` (spacecraft id => fleet entry) introduce, per spacecraft: an entry whose model
  revision differs from the one that spacecraft runs in `running` (the active generation).
  `%{revision_id => %{spacecraft_ids: [id], baselines: [revision_id | nil]}}`; a baseline is the
  revision a moved spacecraft ran before. Grandfathering is per (revision, spacecraft) (director
  11-15): only a spacecraft already on a revision keeps it unapproved; moving any other onto it
  needs the approval.
  """
  @spec introduced(map(), map()) :: map()
  def introduced(entries, running) do
    entries
    |> Enum.flat_map(fn {id, entry} ->
      revision = revision_id(entry)
      before = running_revision(running, id)
      if is_nil(revision) or revision == before, do: [], else: [{revision, id, before}]
    end)
    |> Enum.group_by(&elem(&1, 0))
    |> Map.new(fn {revision, rows} ->
      {revision,
       %{
         spacecraft_ids: rows |> Enum.map(&elem(&1, 1)) |> Enum.sort(),
         baselines: rows |> Enum.map(&elem(&1, 2)) |> Enum.uniq()
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

  @doc """
  What an approval of `revision_id` compares against by default: the revision its catalog
  database's previous import produced; else the revision most spacecraft run now; else nil
  (everything counts as added).
  """
  @spec default_baseline(binary(), binary(), binary()) :: binary() | nil
  def default_baseline(organization_id, mission_id, revision_id) do
    Catalog.previous_model_revision(organization_id, mission_id, revision_id) ||
      organization_id
      |> running_entries(mission_id)
      |> Map.values()
      |> Enum.map(&revision_id/1)
      |> Enum.reject(&(is_nil(&1) or &1 == revision_id))
      |> Enum.frequencies()
      |> Enum.max_by(&elem(&1, 1), fn -> {nil, 0} end)
      |> elem(0)
  end

  @doc "Whether any spacecraft in the active generation runs `revision_id` (a retroactive approval)."
  @spec running?(binary(), binary(), binary()) :: boolean()
  def running?(organization_id, mission_id, revision_id) do
    organization_id
    |> running_entries(mission_id)
    |> Map.values()
    |> Enum.any?(&(revision_id(&1) == revision_id))
  end

  @doc "The ones among `revision_ids` that aren't approved."
  @spec unapproved(binary(), binary(), [binary()]) :: [binary()]
  def unapproved(organization_id, mission_id, revision_ids) do
    statuses = MissionModels.revision_statuses(organization_id, mission_id, revision_ids)
    revision_ids |> Enum.reject(&(statuses[&1] == :approved)) |> Enum.sort()
  end

  @doc """
  For the preview: the target catalogs of `changes` (`%{spacecraft_id => %{to: catalog_id}}`)
  whose mission model isn't approved, with the spacecraft it would be introduced to (those not
  already running it): `[%{catalog_revision_id, catalog_revision_number, catalog_database_id,
  mission_model_revision_id, spacecraft_ids}]`.
  """
  @spec unapproved_targets(binary(), binary(), map()) :: [map()]
  def unapproved_targets(organization_id, mission_id, changes) do
    running = running_entries(organization_id, mission_id)

    targets =
      changes
      |> Enum.group_by(fn {_id, change} -> change.to end, &elem(&1, 0))
      |> Enum.flat_map(&target(organization_id, mission_id, &1, running))

    unapproved =
      MapSet.new(
        unapproved(organization_id, mission_id, Enum.map(targets, & &1.mission_model_revision_id))
      )

    Enum.filter(targets, &MapSet.member?(unapproved, &1.mission_model_revision_id))
  end

  defp target(organization_id, mission_id, {catalog_id, ids}, running) do
    with true <- is_binary(catalog_id),
         {:ok, %{mission_model_revision_id: revision} = catalog} when is_binary(revision) <-
           Catalog.fetch_revision(organization_id, mission_id, catalog_id),
         [_ | _] = moving <- Enum.reject(ids, &(running_revision(running, &1) == revision)) do
      [
        %{
          catalog_revision_id: catalog_id,
          catalog_revision_number: catalog.revision_number,
          catalog_database_id: catalog.catalog_database_id,
          mission_model_revision_id: revision,
          spacecraft_ids: Enum.sort(moving)
        }
      ]
    else
      _none -> []
    end
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

  defp running_revision(running, spacecraft_id),
    do: revision_id(running[spacecraft_id] || running["__mission__"])

  defp revision_id(%{"mission_model" => %{"revision_id" => id}}) when is_binary(id), do: id
  defp revision_id(_entry), do: nil
end
