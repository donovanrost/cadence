defmodule Cadence.Reads.PlanHistory do
  @moduledoc """
  U69 A10 (fe-ops, parity ops (C)): a contact plan's versions and its full decision history,
  for the plan screen's version list and history panel. Open a version with plan detail's
  `?version=`.

    * `versions`, newest first: who cut it and why, its pass counts, its latest decision and
      whether it was submitted;
    * `decisions`, newest first, one entry per act across all rounds: a submit (note, unchanged,
      gap acknowledgements) or a decision (reason, acknowledged exceptions, the automation grant
      it was made under). Actors and the approval words match plan detail's `submission` and
      `approval`.

  At most #{200} versions and #{500} decisions (newest kept), `truncated` past either.
  """

  alias Cadence.Accounts
  alias Cadence.Auth
  alias Cadence.ContactPlanning.{ContactPlanApprovals, ContactPlans, PlanSubmissions}
  alias Cadence.Reads.{PlanApproval, RequirementLabels}

  @max_versions 200
  @max_decisions 500

  @spec load(binary(), binary(), binary()) :: {:ok, map()} | {:error, :plan_not_found}
  def load(org, mission, plan_id) do
    case ContactPlans.fetch(org, mission, plan_id) do
      {:ok, _plan, latest} ->
        versions = ContactPlans.list_versions(org, mission, plan_id)
        approvals = ContactPlanApprovals.list(org, mission, plan_id)
        rounds = PlanSubmissions.list(org, mission, plan_id)
        decisions = org |> decisions_with_labels(mission, rounds, approvals)

        {:ok,
         %{
           plan_id: plan_id,
           latest_version: latest.version,
           versions:
             versions
             |> Enum.take(@max_versions)
             |> Enum.map(&version(&1, org, approvals, rounds)),
           decisions: Enum.take(decisions, @max_decisions),
           truncated: length(versions) > @max_versions or length(decisions) > @max_decisions
         }}

      {:error, _not_found} ->
        {:error, :plan_not_found}
    end
  end

  defp version(version, org, approvals, rounds) do
    latest = Enum.find(approvals, &(&1.contact_plan_version == version.version))

    %{
      version: version.version,
      created_at: version.created_at,
      created_by: creator(org, version.created_by),
      rationale: version.rationale,
      content_sha256: version.content_sha256,
      selected: length(version.selected_snapshot_ids || []),
      locked: length(version.locked_snapshot_ids || []),
      rejected: length(version.rejected_snapshot_ids || []),
      decision: latest && to_string(latest.decision),
      submitted: Enum.any?(rounds, &(&1.contact_plan_version == version.version))
    }
  end

  # ux U73: each acknowledgement and exception names its requirement and spacecraft.
  defp decisions_with_labels(org, mission, rounds, approvals) do
    decisions = decisions(rounds, approvals)

    refs =
      Enum.flat_map(decisions, fn d ->
        Enum.map(d.acknowledgements, &{&1.requirement_id, nil}) ++
          Enum.map(d.exceptions, &{&1.requirement_id, &1.requirement_version})
      end)
      |> Enum.reject(fn {id, _version} -> is_nil(id) end)

    labels = RequirementLabels.load(org, mission, refs)

    Enum.map(decisions, fn d ->
      %{
        d
        | acknowledgements:
            Enum.map(d.acknowledgements, &label(&1, labels, {&1.requirement_id, nil})),
          exceptions:
            Enum.map(
              d.exceptions,
              &label(&1, labels, {&1.requirement_id, &1.requirement_version})
            )
      }
    end)
  end

  defp label(item, labels, ref) do
    found = Map.get(labels, ref)

    Map.merge(item, %{
      requirement_label: found && found.name,
      spacecraft: found && found.spacecraft
    })
  end

  defp decisions(rounds, approvals) do
    round_of = Map.new(rounds, &{&1.contact_plan_version, &1.round})

    submits =
      Enum.map(rounds, fn round ->
        %{
          kind: "submitted",
          version: round.contact_plan_version,
          round: round.round,
          actor: actor(round.actor_document),
          at: round.submitted_at,
          text: round.note,
          unchanged: round.unchanged,
          acknowledgements:
            Enum.map(
              round.acknowledgements_document || [],
              &%{requirement_id: &1["requirement_id"], reason: &1["reason"]}
            ),
          exceptions: [],
          automation_grant_id: nil
        }
      end)

    decided =
      Enum.map(approvals, fn approval ->
        view = PlanApproval.view(approval)

        %{
          kind: to_string(approval.decision),
          version: approval.contact_plan_version,
          round: Map.get(round_of, approval.contact_plan_version),
          actor: view.actor,
          at: view.at,
          text: view.reason,
          unchanged: nil,
          acknowledgements: [],
          exceptions: view.exceptions,
          automation_grant_id: approval.automation_grant_id
        }
      end)

    Enum.sort_by(submits ++ decided, &DateTime.to_unix(&1.at, :microsecond), :desc)
  end

  defp actor(%{} = doc), do: %{kind: doc["kind"], id: doc["id"], name: doc["name"]}
  defp actor(_none), do: nil

  # A version's `created_by` is an actor id: a person, a service identity, or Cadence's planner.
  defp creator(_org, nil), do: nil

  # As plan detail's `created_by`: an automatic run's id reads as Cadence itself.
  defp creator(_org, "cadence" <> _ = id), do: %{kind: "system", id: id, name: "Cadence"}
  defp creator(_org, "system" <> _ = id), do: %{kind: "system", id: id, name: "Cadence"}

  defp creator(org, id) do
    case Accounts.fetch_user(id) do
      {:ok, user} ->
        %{kind: "user", id: id, name: user.display_name || user.email}

      _not_user ->
        case Auth.fetch_service_identity(org, id) do
          {:ok, service} -> %{kind: "service_identity", id: id, name: service.display_name}
          _not_service -> %{kind: "system", id: id, name: nil}
        end
    end
  end
end
