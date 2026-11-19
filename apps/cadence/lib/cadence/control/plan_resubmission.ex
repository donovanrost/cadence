defmodule Cadence.Control.PlanResubmission do
  @moduledoc """
  U36 (qa #40): submitting a contact plan, including a draft whose current version an approver
  sent back. Decisions bind to a version, so a sent-back (rejected) version can't be submitted
  again: the server cuts the next version with the same selection (`rationale: "Resubmitted
  after send back"`) and submits that; the rejection stays on the old version. Approved or
  undecided versions keep the plain submit.

  The lock, the `expected_version` check, the cut, the submit and the round record are one
  transaction under the plan row lock, so a double-click can't cut twice: the second request
  finds a newer version and gets `contact_plan_version_changed` (domain review).

  Every submit is a round (`ContactPlanning.PlanSubmissions`): actor, an optional note for the
  reviewer, whether the version's selection is unchanged from the previous version, and the
  author's gap acknowledgements.

  #257 (director 11-19): submit only submits. A plan already pending approval is refused
  (`{:contact_plan_already_submitted, details}`), never passed through; approving is its own
  action. The console's operation id is checked after the plan row lock and recorded with the
  answer in the same transaction (`ContactPlanning.PlanOperations`): the same request again gets
  `{:replayed, answer}`.
  """

  alias Cadence.Auth.Scope

  alias Cadence.ContactPlanning.{
    ContactPlan,
    ContactPlanApprovals,
    ContactPlans,
    PlanOperations,
    PlanSubmissions,
    PlanUpdates
  }

  alias Cadence.Management.Contacts, as: ManagementContacts
  alias Cadence.Repo

  @rationale "Resubmitted after send back"
  @default_reason "Submitted from the console contact plan"

  @doc """
  Locks the plan and submits a draft (cutting a new version first when it was sent back);
  `check.(version)` runs before the submit (station availability). `params.operation_id` is the
  console's operation id. Returns `{:ok, {:submitted, answer}}` or, for the same request again,
  `{:ok, {:replayed, answer}}`, where `answer` is `{200, body}` and the body names the version
  put up for approval. A plan already pending approval is refused with who sent it and when;
  other states can't be submitted.
  """
  @spec submit(Scope.t(), binary(), binary(), map(), (struct() -> :ok | {:error, term()})) ::
          {:ok, {:submitted | :replayed, PlanOperations.answer()}} | {:error, term()}
  def submit(%Scope{} = scope, mission_id, plan_id, params, check) do
    Repo.transaction(fn ->
      with {:ok, plan, version} <-
             ContactPlans.fetch_locked(scope.organization_id, mission_id, plan_id),
           :new <- operation(scope, mission_id, plan_id, params),
           :ok <- not_pending(scope.organization_id, mission_id, plan, version),
           :ok <- expected(version.version, params[:expected_version]),
           {:ok, plan, version} <- cut_if_sent_back(scope, mission_id, plan, version),
           :ok <- check.(version),
           {:ok, plan} <- submit_draft(scope, mission_id, plan, version, params),
           {:ok, _round} <- record(scope, mission_id, plan, version, params),
           answer = {200, body(plan, version)},
           :ok <-
             PlanOperations.record(operation_attrs(scope, mission_id, plan_id, params), answer) do
        {:submitted, answer}
      else
        {:replay, answer} -> {:replayed, answer}
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, {:submitted, _answer} = result} ->
        # After the commit (domain review): publishes from inside the transaction are delayed,
        # but a slow commit could outlast that, and a rolled-back submit shouldn't be announced.
        PlanUpdates.changed(scope.organization_id, mission_id)
        {:ok, result}

      {:ok, {:replayed, _answer} = result} ->
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp operation(scope, mission_id, plan_id, params) do
    case PlanOperations.check(
           scope.organization_id,
           mission_id,
           params.operation_id,
           plan_id,
           :submit,
           actor(scope)["id"],
           params
         ) do
      :new -> :new
      {:replay, answer} -> {:replay, answer}
      :duplicate_operation -> {:error, :duplicate_operation}
      :operation_conflict -> {:error, :operation_already_claimed}
    end
  end

  defp operation_attrs(scope, mission_id, plan_id, params),
    do: %{
      organization_id: scope.organization_id,
      mission_id: mission_id,
      operation_id: params.operation_id,
      contact_plan_id: plan_id,
      action: :submit,
      actor_id: actor(scope)["id"],
      request: params
    }

  defp body(plan, version),
    do: %{
      "plan_id" => plan.contact_plan_id,
      "version" => version.version,
      "state" => "pending_approval",
      "outcome" => "pending_approval"
    }

  # #257: a plan already waiting for approval is refused, with who sent it and when (both or
  # neither, U29), from its latest round.
  defp not_pending(
         organization_id,
         mission_id,
         %ContactPlan{lifecycle_state: :pending_approval} = plan,
         version
       ) do
    details =
      organization_id
      |> PlanSubmissions.list(mission_id, plan.contact_plan_id)
      |> Enum.find(&(&1.contact_plan_version == version.version))
      |> case do
        %{actor_document: %{"id" => id} = actor, submitted_at: at} ->
          %{submitted_by: %{id: id, name: actor["name"]}, submitted_at: at}

        _none ->
          %{submitted_by: nil, submitted_at: nil}
      end

    {:error, {:contact_plan_already_submitted, details}}
  end

  defp not_pending(_organization_id, _mission_id, _plan, _version), do: :ok

  defp cut_if_sent_back(scope, mission_id, %ContactPlan{lifecycle_state: :draft} = plan, version) do
    if sent_back?(scope.organization_id, mission_id, plan.contact_plan_id, version.version) do
      ManagementContacts.version_plan(scope, mission_id, plan.contact_plan_id, version.version, %{
        selected_snapshot_ids: version.selected_snapshot_ids || [],
        locked_snapshot_ids: version.locked_snapshot_ids || [],
        rationale: @rationale
      })
    else
      {:ok, plan, version}
    end
  end

  defp cut_if_sent_back(_scope, _mission_id, plan, version), do: {:ok, plan, version}

  defp submit_draft(
         scope,
         mission_id,
         %ContactPlan{lifecycle_state: :draft} = plan,
         version,
         params
       ),
       do:
         ManagementContacts.submit_plan(
           scope,
           mission_id,
           plan.contact_plan_id,
           version.version,
           reason(params[:note] || params[:reason])
         )

  defp submit_draft(_scope, _mission_id, _plan, _version, _params),
    do: {:error, :contact_plan_not_submittable}

  defp record(scope, mission_id, plan, version, params) do
    PlanSubmissions.record(%{
      organization_id: scope.organization_id,
      mission_id: mission_id,
      contact_plan_id: plan.contact_plan_id,
      contact_plan_version: version.version,
      actor_document: actor(scope),
      note: params[:note],
      unchanged: unchanged?(scope.organization_id, mission_id, plan.contact_plan_id, version),
      acknowledgements:
        Enum.map(params[:acknowledgements] || [], fn ack ->
          %{"requirement_id" => ack.requirement_id, "reason" => ack.reason}
        end)
    })
  end

  # Domain: unchanged = selected and locked ids equal the previous version's (not a hash compare).
  defp unchanged?(_organization_id, _mission_id, _plan_id, %{version: 1}), do: false

  defp unchanged?(organization_id, mission_id, plan_id, version) do
    case ContactPlans.fetch_version(organization_id, mission_id, plan_id, version.version - 1) do
      {:ok, previous} -> ids(previous) == ids(version)
      _missing -> false
    end
  end

  defp ids(version),
    do:
      {MapSet.new(version.selected_snapshot_ids || []),
       MapSet.new(version.locked_snapshot_ids || [])}

  # Only a rejected (sent back) decision on the current version cuts a new one.
  defp sent_back?(organization_id, mission_id, plan_id, version) do
    organization_id
    |> ContactPlanApprovals.list(mission_id, plan_id)
    |> Enum.filter(&(&1.contact_plan_version == version))
    |> Enum.max_by(&DateTime.to_unix(&1.decided_at, :microsecond), fn -> nil end)
    |> case do
      %{decision: :rejected} -> true
      _other -> false
    end
  end

  defp expected(version, version), do: :ok
  defp expected(_current, _expected), do: {:error, :contact_plan_version_changed}

  defp reason(reason) when is_binary(reason) and byte_size(reason) > 0, do: reason
  defp reason(_reason), do: @default_reason

  defp actor(%Scope{user: %{user_id: id} = user}),
    do: %{"kind" => "user", "id" => id, "name" => user.display_name || user.email}

  defp actor(%Scope{service_identity: %{service_identity_id: id} = identity}),
    do: %{"kind" => "service", "id" => id, "name" => Map.get(identity, :display_name)}

  defp actor(_scope), do: %{"kind" => "unknown"}
end
