defmodule Cadence.Control.ActivationRequests.Refusals do
  @moduledoc """
  The approve preflight's refusals, as the console's decide panel words them (ux U95; domain's
  one check list, director 11-17): an approval is refused BEFORE anything is recorded when the
  request couldn't apply. Each becomes `{:approve_refused, code, details}` (a 409); the details
  name what the words need: the catalog revisions behind an unapproved model, the report of a
  failed comparison, the spacecraft of a stale review.
  """

  alias Cadence.Catalog.{FleetSnapshot, ModelRevisions}
  alias Cadence.Control.Activations.Description
  alias Cadence.SpacecraftStore

  @plain ~w(approved_activation_content_mismatch change_set_activation_stale
            mission_model_activation_manifest_required mission_model_comparison_report_required
            invalid_mission_model_activation_manifest mission_model_runtime_plans_not_ready
            mission_model_runtime_plan_manifest_mismatch invalid_spacecraft_model_bindings
            spacecraft_configuration_review_required)a

  @doc "The approve result, with a preflight refusal explained; anything else unchanged."
  @spec explain(term(), binary(), binary(), map()) :: term()
  # #236: the approver authored content being activated. Not a preflight refusal (a 403, not a
  # 409): it names the reviewed spacecraft they saved, as the stale review does.
  # #236 (lead's ruling b): the authors couldn't be determined, so the check fails closed. The
  # same 403 path, naming the craft whose authors couldn't be read ([] when none can be named).
  def explain({:error, {code, ids}}, org, mission, _request)
      when code in [:activation_approver_authored_content, :activation_approver_authors_unknown] and
             is_list(ids),
      do: {:error, {code, %{spacecraft_ids: ids, spacecraft: named(org, mission, ids)}}}

  def explain({:error, reason}, org, mission, request) do
    case refusal(reason, org, mission, request) do
      nil -> {:error, reason}
      {code, details} -> {:error, {:approve_refused, code, details}}
    end
  end

  def explain(result, _org, _mission, _request), do: result

  defp refusal(code, _org, _mission, _request) when code in @plain, do: {code, nil}

  defp refusal(:mission_model_revision_not_approved, org, mission, request),
    do: not_approved(org, mission, models(request))

  defp refusal({:mission_model_revision_not_approved, ids}, org, mission, _request)
       when is_list(ids),
       do: not_approved(org, mission, ids)

  defp refusal(:mission_model_revision_not_in_catalog, _org, _mission, request),
    do: {:mission_model_revision_not_in_catalog, %{mission_model_revision_ids: models(request)}}

  defp refusal({:mission_model_comparison_failed, revision, report}, org, mission, _request),
    do:
      {:mission_model_comparison_failed,
       %{
         catalog_revision:
           org |> ModelRevisions.for_models(mission, [revision]) |> catalog(revision),
         # fe-ops: the report opens on the model revision's approval page.
         mission_model_revision_id: revision,
         comparison_report_id: report
       }}

  # Both name the reviewed craft (ux U95).
  defp refusal(code, org, mission, request)
       when code in [:spacecraft_configuration_review_stale, :spacecraft_model_not_active] do
    case Description.describe(request.metadata || %{}).spacecraft_ids do
      [] -> {code, nil}
      ids -> {code, %{spacecraft_ids: ids, spacecraft: named(org, mission, ids)}}
    end
  end

  defp refusal({:mission_model_manifest_mismatch, field}, _org, _mission, _request),
    do: {:mission_model_manifest_mismatch, %{field: to_string(field)}}

  defp refusal(_reason, _org, _mission, _request), do: nil

  defp not_approved(org, mission, ids) do
    catalogs = ModelRevisions.for_models(org, mission, ids)

    {:mission_model_revision_not_approved,
     %{
       catalog_revisions:
         Enum.map(ids, fn id ->
           named = catalog(catalogs, id) || %{id: nil, number: nil}
           Map.put(named, :mission_model_revision_id, id)
         end)
     }}
  end

  defp catalog(catalogs, model_id) do
    case Map.get(catalogs, model_id) do
      %{id: id, number: number} -> %{id: id, number: number}
      nil -> nil
    end
  end

  # ux names the craft ("EARENDIL-004's configuration"); at most the first 5, as L10 shows.
  defp named(org, mission, ids) do
    shown = Enum.take(ids, 5)

    found =
      case SpacecraftStore.fetch_spacecrafts(org, mission, shown) do
        {:ok, found} -> found
        {:error, _bounds} -> %{}
      end

    Enum.map(shown, &%{id: &1, name: found[&1] && found[&1].display_name})
  end

  # The model revisions a request activates: its own manifest's, or each fleet entry's.
  defp models(request) do
    metadata = request.metadata || %{}

    case get_in(metadata, ["mission_model", "revision_id"]) do
      id when is_binary(id) -> [id]
      _fleet -> fleet_models(metadata)
    end
  end

  defp fleet_models(metadata) do
    case FleetSnapshot.entries(metadata) do
      {:ok, entries} ->
        entries
        |> Enum.map(fn {_id, entry} -> get_in(entry, ["mission_model", "revision_id"]) end)
        |> Enum.filter(&is_binary/1)
        |> Enum.uniq()

      _invalid ->
        []
    end
  end
end
