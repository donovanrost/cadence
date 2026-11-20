defmodule Cadence.Reads.MissionModelApprovals do
  @moduledoc """
  The console's model approval gate (ux U65, DECISIONS #92 a; fe-ops' reader): a mission-model
  revision named by its catalog revision ("catalog rev 4"), its decision, the latest comparison
  report (summarised: totals and per-kind sections, never the raw declaration lists), and what
  the viewer may do. Decisions go through `MissionModels.approve_revision/5` and
  `reject_revision/5`; a comparison runs against the mission's active binding set (none for a
  mission's first revision) and the revision this one replaces (none when there's nothing
  earlier: `against` null, ux U90).
  """

  alias Cadence.Accounts.MemberNames
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Catalog
  alias Cadence.Catalog.ModelRevisions
  alias Cadence.Control.{Activations, ModelApprovalGate}
  alias Cadence.MissionModels
  alias Cadence.MissionModels.{ApprovalReads, Comparison, RevisionDecisions}
  alias Cadence.Reads.Catalog.RevisionBase

  @spec list(Scope.t(), binary(), binary()) :: [map()]
  def list(%Scope{} = scope, mission_id, status) do
    org = scope.organization_id
    rows = ApprovalReads.list(org, mission_id, status)
    ids = Enum.map(rows, & &1.id)
    catalogs = ModelRevisions.for_models(org, mission_id, ids)
    statuses = ApprovalReads.latest_statuses(org, mission_id, ids)

    firsts =
      Map.new(rows, &{&1.id, org |> Catalog.model_importers(mission_id, &1.id) |> List.first()})

    names = MemberNames.members(org, firsts |> Map.values() |> Enum.reject(&is_nil/1))

    Enum.map(rows, fn row ->
      %{
        id: row.id,
        status: row.status,
        imported_at: row.imported_at,
        imported_by: person_or_nil(firsts[row.id], names),
        catalog_revision: Map.get(catalogs, row.id),
        latest_comparison_status: Map.get(statuses, row.id)
      }
    end)
  end

  @spec read(Scope.t(), binary(), binary()) :: {:ok, map()} | {:error, term()}
  def read(%Scope{} = scope, mission_id, revision_id) do
    org = scope.organization_id

    with {:ok, row} <- ApprovalReads.fetch(org, mission_id, revision_id) do
      importers = Catalog.model_importers(org, mission_id, revision_id)
      plans_ready = ApprovalReads.plans_ready?(org, mission_id, revision_id)

      report =
        org |> ApprovalReads.latest_reports(mission_id, [revision_id]) |> Map.get(revision_id)

      viewer_id = scope.user && scope.user.user_id
      {blocked, blocked_details} = cannot_decide(scope, mission_id, row, plans_ready)

      catalog_revision =
        case ModelRevisions.first_for_model(org, mission_id, row.id) do
          nil -> nil
          revision -> catalog_revision(org, mission_id, revision)
        end

      {:ok,
       %{
         id: row.id,
         status: row.status,
         imported_at: row.imported_at,
         imported_by: first_importer(org, importers),
         catalog_revision: catalog_revision,
         decision: decision(row),
         viewer_can_decide: is_nil(blocked),
         viewer_is_importer: is_binary(viewer_id) and viewer_id in importers,
         cannot_decide_because: blocked,
         # #280 (ux U100): via_service for self_approval through a service; service for
         # authors_unknown. Nil otherwise.
         cannot_decide_details: blocked_details,
         # Approve only (lead 11-17, ux U88): no catalog revision names this model revision, so
         # domain's guard refuses approving it; Reject stays. cannot_decide_because wins if set.
         cannot_approve_because: if(is_nil(catalog_revision), do: "not_in_catalog"),
         plans_ready: plans_ready,
         comparison: report && summary(org, mission_id, report)
       }}
    end
  end

  @doc """
  Approves against `report_id`; retroactive when a spacecraft already runs the revision (grandfathered,
  domain 71ce7d850), which the approval records and the audit says.
  """
  @spec approve(Scope.t(), binary(), binary(), binary()) :: {:ok, term()} | {:error, term()}
  def approve(%Scope{} = scope, mission_id, revision_id, report_id) do
    retroactive = ModelApprovalGate.running?(scope.organization_id, mission_id, revision_id)

    MissionModels.approve_revision(scope, mission_id, revision_id, report_id,
      retroactive: retroactive
    )
  end

  @doc "Runs a comparison for the revision (synchronous; reports dedupe on content)."
  @spec compare(Scope.t(), binary(), binary()) :: {:ok, map()} | {:error, term()}
  def compare(%Scope{} = scope, mission_id, revision_id) do
    org = scope.organization_id

    with {:ok, _row} <- ApprovalReads.fetch(org, mission_id, revision_id),
         {:ok, basis} <- active_basis(org, mission_id),
         {:ok, report} <-
           Comparison.run(
             org,
             mission_id,
             revision_id,
             basis.binding_set_id,
             basis.binding_set_version,
             baseline_revision_id: baseline(org, mission_id, revision_id)
           ) do
      {:ok, summary(org, mission_id, Map.put_new(report, "generated_at", DateTime.utc_now()))}
    end
  end

  # -- the report, summarised for the screen ----------------------------------------------

  defp summary(org, mission_id, report) do
    static = report["static"] || %{}
    replay = report["replay"] || %{}
    against = report["baseline_revision_id"]
    kinds = kinds(org, mission_id, report["candidate_revision_id"], against)

    %{
      report_id: report["comparison_report_id"],
      passed: report["status"] == "passed",
      against: against && against(org, mission_id, against),
      replay: replay(replay),
      risk: report["risk"],
      totals: totals(static),
      sections: sections(static, kinds),
      affected_kinds: static["affected_kinds"] || [],
      changed_targets: Enum.map(static["changed_targets"] || [], &to_string/1),
      generated_at: report["generated_at"]
    }
  end

  defp replay(replay) do
    cases = replay["cases"] || []

    %{
      status: replay["status"],
      reason: replay["reason"],
      cases: length(cases),
      failed_cases:
        for(%{"status" => "failed"} = c <- cases, do: %{name: c["name"], reason: c["reason"]})
    }
  end

  defp totals(static),
    do: %{
      added: length(static["added"] || []),
      removed: length(static["removed"] || []),
      changed: length(static["changed"] || [])
    }

  defp against(org, mission_id, revision_id) do
    %{
      revision_id: revision_id,
      catalog_revision_number:
        org
        |> ModelRevisions.for_models(mission_id, [revision_id])
        |> get_in([revision_id, :number])
    }
  end

  # Declaration keys → kind, from the candidate (added, changed) and the baseline (removed).
  defp kinds(org, mission_id, candidate_id, baseline_id) do
    [candidate_id, baseline_id]
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(%{}, &Map.merge(declaration_kinds(org, mission_id, &1), &2))
  end

  defp declaration_kinds(org, mission_id, revision_id) do
    case MissionModels.fetch_revision(org, mission_id, revision_id) do
      {:ok, revision} ->
        Map.new(revision.declarations, &{elem(&1, 0), to_string(elem(&1, 1).kind)})

      _missing ->
        %{}
    end
  end

  defp kind_changes(change, static, kinds),
    do: for(key <- static[to_string(change)] || [], do: {Map.get(kinds, key, "unknown"), change})

  defp sections(static, kinds) do
    [:added, :removed, :changed]
    |> Enum.flat_map(&kind_changes(&1, static, kinds))
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {kind, changes} ->
      counts = Enum.frequencies(changes)

      %{
        kind: kind,
        added: Map.get(counts, :added, 0),
        removed: Map.get(counts, :removed, 0),
        changed: Map.get(counts, :changed, 0)
      }
    end)
    |> Enum.sort_by(& &1.kind)
  end

  # -- decisions and the viewer -----------------------------------------------------------

  defp decision(%{status: "approved", approved_by: by, approved_at: at}),
    do: %{
      kind: "approved",
      by: person(by),
      at: at,
      report_id: by["comparison_report_id"],
      reason: nil,
      retroactive: by["retroactive"] == true
    }

  defp decision(%{status: "rejected", rejected_by: by, rejected_at: at}),
    do: %{
      kind: "rejected",
      by: person(by),
      at: at,
      report_id: nil,
      reason: by && by["reason"],
      retroactive: false
    }

  defp decision(_row), do: nil

  defp person(%{"id" => id} = by), do: %{id: id, name: by["display_name"] || by["name"]}
  defp person(_none), do: nil

  # The first reason the viewer can't decide, in ux's order (nil when they can), with the separation
  # refusal's details when that's the reason.
  defp cannot_decide(scope, mission_id, row, plans_ready) do
    viewer_id = scope.user && scope.user.user_id

    cond do
      Policy.authorize(scope, :approve_mission_model, %{
        organization_id: scope.organization_id,
        mission_id: mission_id
      }) != :ok ->
        {"not_admin", nil}

      row.status != "candidate" ->
        {"not_approvable", nil}

      true ->
        case RevisionDecisions.separation(scope.organization_id, mission_id, row.id, viewer_id) do
          {:refused, refusal} -> separation_reason(refusal)
          {:ok, _checked} when not plans_ready -> {"plans_not_ready", nil}
          {:ok, _checked} -> {nil, nil}
        end
    end
  end

  # The list's catalog revision fields (ModelRevisions.for_models/3) plus #195's (ux U102): the
  # run that made it and its breaking count against the revision before it in its database, the
  # base the import page's C3 diff uses (RevisionBase). One row, so every key or none.
  defp catalog_revision(org, mission_id, revision) do
    Map.merge(
      %{
        id: revision.catalog_revision_id,
        number: revision.revision_number,
        label: revision.revision_label,
        database_id: revision.catalog_database_id,
        import_run_id: revision.import_run_id
      },
      RevisionBase.breaking(org, mission_id, revision)
    )
  end

  defp separation_reason(%{reason: :self, via_service: nil}), do: {"self_approval", nil}

  defp separation_reason(%{reason: :self, via_service: via}),
    do: {"self_approval", %{via_service: via}}

  defp separation_reason(%{reason: :authors_unknown, service: service}),
    do: {"authors_unknown", %{service: service}}

  # #366 (mms-security, #146's rule): the importer is named only while an active member of the
  # mission's organization, checked at read time, and never by email. An active member with no
  # display name keeps their id with `name: nil` (api-ops on #487: membership, not a name, is the
  # line for the id, as Configuration.ActorNames). Anyone else (a platform admin from another
  # organization, someone who has left) is `%{id: nil, name: nil}`, so neither their name nor their
  # id reaches this organization; it still reads as recorded, not as "Importer not recorded".
  defp first_importer(org, [id | _]),
    do: person_or_nil(id, MemberNames.members(org, [id]))

  defp first_importer(_org, []), do: nil

  defp person_or_nil(nil, _names), do: nil

  defp person_or_nil(id, names) do
    case Map.fetch(names, id) do
      {:ok, name} -> %{id: id, name: name}
      :error -> %{id: nil, name: nil}
    end
  end

  # -- comparison inputs ------------------------------------------------------------------

  defp active_basis(org, mission_id) do
    case Activations.fetch_active_basis(org, mission_id) do
      {:ok, %{binding_set_id: id, binding_set_version: version}} when is_binary(id) ->
        {:ok, %{binding_set_id: id, binding_set_version: version}}

      # A mission's first revision (domain/lead 11-17, ux U90): nothing runs yet, so there's no
      # binding set to record; the comparison runs against no baseline (every item added).
      _none ->
        {:ok, %{binding_set_id: nil, binding_set_version: nil}}
    end
  end

  # domain 11-15: the previous import of the same catalog database, else the revision most craft
  # run, else none (everything counts as added).
  defp baseline(org, mission_id, revision_id),
    do: ModelApprovalGate.default_baseline(org, mission_id, revision_id)
end
