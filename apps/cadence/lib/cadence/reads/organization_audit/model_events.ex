defmodule Cadence.Reads.OrganizationAudit.ModelEvents do
  @moduledoc """
  Model approval decisions in the organization audit (director 11-15, ux U65), kind `config`,
  named by catalog revision as the screen does:

    * "Approved catalog rev 4 (comparison passed against rev 3; replay not run)"
    * "Approved catalog rev 1 (not compared: no earlier configuration; replay not run)" (ux U90)
    * "Rejected catalog rev 4", with the reason in the reason column.

  From `MissionModels.list_model_decisions/2` (people only, with the evidence they decided on);
  nothing new is written.
  """

  alias Cadence.Catalog.ModelRevisions
  alias Cadence.MissionModels
  alias Cadence.MissionModels.ApprovalReads

  @replay %{
    "not_run" => "replay not run",
    "not_required" => "replay not needed",
    "passed" => "replay passed",
    "failed" => "replay failed"
  }

  @spec list(binary(), binary()) :: [map()]
  def list(organization_id, mission_id) do
    decisions = MissionModels.list_model_decisions(organization_id, mission_id)

    reports =
      decisions
      |> Enum.map(& &1.evidence["comparison_report_id"])
      |> Enum.reject(&is_nil/1)
      |> then(&ApprovalReads.reports(organization_id, mission_id, &1))

    baselines = reports |> Map.values() |> Enum.map(& &1["baseline_revision_id"])

    numbers =
      ModelRevisions.for_models(
        organization_id,
        mission_id,
        (Enum.map(decisions, & &1.revision_id) ++ baselines)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
      )

    Enum.map(decisions, &entry(&1, reports, numbers))
  end

  defp entry(%{decision: :approved, evidence: evidence} = decision, reports, numbers) do
    report = Map.get(reports, evidence["comparison_report_id"], %{})
    label = label(decision.revision_id, numbers)
    detail = detail(report, numbers, evidence["replay"], evidence["retroactive"] == true)
    event(decision, "Approved #{label}#{detail}", label, nil)
  end

  defp entry(%{decision: :rejected, evidence: evidence} = decision, _reports, numbers) do
    label = label(decision.revision_id, numbers)
    event(decision, "Rejected #{label}", label, evidence["reason"])
  end

  defp detail(report, numbers, replay, retroactive) do
    against =
      case report["baseline_revision_id"] do
        # ux U90: nothing earlier to compare with is never 'passed'.
        nil -> "not compared: no earlier configuration"
        id -> "comparison passed against #{short(id, numbers)}"
      end

    prefix = if retroactive, do: "retroactive; ", else: ""

    case Map.get(@replay, replay || get_in(report, ["replay", "status"])) do
      nil -> " (#{prefix}#{against})"
      words -> " (#{prefix}#{against}; #{words})"
    end
  end

  defp event(decision, action, label, reason) do
    %{
      id: "config:mission_model_revision:#{decision.revision_id}:#{decision.decision}",
      at: decision.at,
      actor: %{kind: "user", id: decision.by["id"], name: decision.by["display_name"]},
      kind: "config",
      action: action,
      target: %{kind: "mission_model_revision", id: decision.revision_id, label: label},
      mission: nil,
      reason: reason
    }
  end

  defp label(id, numbers) do
    case get_in(numbers, [id, :number]) do
      nil -> "a catalog revision"
      number -> "catalog rev #{number}"
    end
  end

  defp short(id, numbers) do
    case get_in(numbers, [id, :number]) do
      nil -> "the previous revision"
      number -> "rev #{number}"
    end
  end
end
