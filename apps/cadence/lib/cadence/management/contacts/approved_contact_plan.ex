defmodule Cadence.Management.Contacts.ApprovedContactPlan do
  @moduledoc """
  Immutable Management-plane fact authorizing one exact Contact Plan version.

  Control consumes this fact idempotently. It never selects a mutable Plan
  version or infers approval from a workflow projection.
  """

  alias Cadence.ContactPlanning.{ContactPlan, ContactPlanApproval, ContactPlanVersion}
  alias Cadence.Platform.ContentHash

  @type t :: %__MODULE__{
          approval_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          contact_plan_id: binary(),
          contact_plan_version: pos_integer(),
          content_sha256: binary(),
          opportunity_snapshot_ids: [binary()],
          actor_id: binary(),
          actor_kind: :user | :service,
          decided_at: DateTime.t(),
          idempotency_key: binary()
        }

  @enforce_keys [
    :approval_id,
    :organization_id,
    :mission_id,
    :contact_plan_id,
    :contact_plan_version,
    :content_sha256,
    :opportunity_snapshot_ids,
    :actor_id,
    :actor_kind,
    :decided_at,
    :idempotency_key
  ]
  defstruct @enforce_keys

  @spec new(ContactPlan.t(), ContactPlanVersion.t(), ContactPlanApproval.t(), [binary()]) ::
          {:ok, t()} | {:error, term()}
  def new(
        %ContactPlan{} = plan,
        %ContactPlanVersion{} = version,
        %ContactPlanApproval{} = approval,
        opportunity_snapshot_ids
      )
      when is_list(opportunity_snapshot_ids) do
    with :ok <- approved_plan(plan, version),
         :ok <- exact_approval(approval, version),
         :ok <- exact_scope(plan, version, approval),
         :ok <- valid_snapshot_ids(opportunity_snapshot_ids) do
      {:ok,
       %__MODULE__{
         approval_id: approval.contact_plan_approval_id,
         organization_id: plan.organization_id,
         mission_id: plan.mission_id,
         contact_plan_id: plan.contact_plan_id,
         contact_plan_version: version.version,
         content_sha256: version.content_sha256,
         opportunity_snapshot_ids: opportunity_snapshot_ids,
         actor_id: approval.actor_id,
         actor_kind: approval.actor_kind,
         decided_at: approval.decided_at,
         idempotency_key:
           "cadence:approved-contact-plan:" <>
             ContentHash.term_sha256(%{
               "approval_id" => approval.contact_plan_approval_id,
               "plan_id" => plan.contact_plan_id,
               "version" => version.version,
               "content_sha256" => version.content_sha256
             })
       }}
    end
  end

  defp approved_plan(
         %ContactPlan{lifecycle_state: state, approved_version: version},
         %{version: version}
       )
       when state in [:approved, :executing, :partially_reserved, :reserved, :failed],
       do: :ok

  defp approved_plan(_plan, _version), do: {:error, :contact_plan_not_approved}

  defp exact_approval(
         %ContactPlanApproval{
           decision: :approved,
           contact_plan_version: version,
           content_sha256: hash
         },
         %{version: version, content_sha256: hash}
       ),
       do: :ok

  defp exact_approval(_approval, _version), do: {:error, :contact_plan_approval_not_exact}

  defp exact_scope(plan, version, approval) do
    scopes =
      Enum.map([plan, version, approval], fn item ->
        {item.organization_id, item.mission_id, item.contact_plan_id}
      end)

    if Enum.uniq(scopes) == [hd(scopes)],
      do: :ok,
      else: {:error, :contact_plan_approval_scope_mismatch}
  end

  defp valid_snapshot_ids(ids) do
    if Enum.all?(ids, &(is_binary(&1) and &1 != "")) and Enum.uniq(ids) == ids,
      do: :ok,
      else: {:error, :approved_contact_plan_snapshots_invalid}
  end
end
