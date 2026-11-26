defmodule Cadence.Governance.DecisionRecord do
  @moduledoc """
  The four-eyes decision record contract (BACKLOG P3, director 11-17; design:
  var/four-eyes-record-design.md §1 and §4). Every path that records a human decision on a change
  (change sets, activations, commanding, contact plans, fleet policies, provider changes) keeps
  its own table, written in the same transaction as the change it gates, and builds the row
  through this struct, so the contract can't drift between paths.

  - `actor`: `{kind, id}`, only from the session scope (`Scope.audit_actor/1`), never a parameter.
  - `decision`: approved, rejected, sent_back, withdrawn, acknowledged, or `not_required` (the
    policy needed no second person, so the act went straight through). Automation grants (#283,
    api-ops 11-19) add `proposed` (what a second person will approve), `revoked` and `narrowed`
    (tightenings: never refused for want of a reason or digest).
  - `reason`: required for rejected, sent_back and withdrawn; optional otherwise. Blank after
    trimming counts as absent.
  - `decided_at`: server time.
  - `subject`: what was reviewed, `%{kind, id, version, digest, previous_digest}`. `digest` is the
    content hash or the review token the approver's screen carried; required for approved,
    not_required, proposed and narrowed, since the apply compares its own digest with it
    (approved = applied). `previous_digest` is set only for narrowed (the content it replaced).
  - `policy`: the policy snapshot or token at decision time.
  - `separated_from`: the actor ids the separation check compared against (author, submitter,
    importer, requester); empty when the policy didn't require separation.
  - `admin_mode`: whether the decider acted in platform admin mode, from the scope.

  Decision rows are INSERT-ONLY and never deleted (DECISIONS #107): the tables in `tables/0` carry
  database triggers refusing UPDATE, DELETE and TRUNCATE, and an ExUnit guard checks them.
  """

  alias Cadence.Auth.Scope

  # #499 (api-ops' contract): `suspended` (a tightening of the approval setting, never blocked:
  # the server records the hash, none is required) and `resumed` (an approval-like act on the
  # hash the approver saw).
  @decisions ~w(approved rejected sent_back withdrawn acknowledged not_required proposed revoked narrowed suspended resumed)a
  @reason_required ~w(rejected sent_back withdrawn)a
  @digest_required ~w(approved not_required proposed narrowed resumed)a

  # Pure decision tables: append-only, guarded by triggers (migration
  # 20261117160000_decision_records_append_only). A path joins by adding its table here.
  @tables ~w(
    mission_config_reviews
    mission_config_revisions
    activation_decisions
    command_approvals
    contact_plan_approvals
    contact_plan_submissions
    fleet_planning_policy_approvals
    provider_change_approvals
    automation_grant_decisions
    spacecraft_configuration_reviews
    spacecraft_configuration_review_members
    activation_change_set_spacecraft
    mission_model_decisions
  )

  @enforce_keys [:actor, :decision, :decided_at, :subject]
  defstruct [
    :actor,
    :decision,
    :reason,
    :decided_at,
    :subject,
    :policy,
    :admin_mode,
    separated_from: []
  ]

  @type subject :: %{
          required(:kind) => String.t(),
          required(:id) => String.t(),
          optional(:version) => integer() | nil,
          optional(:digest) => String.t() | nil,
          optional(:previous_digest) => String.t() | nil
        }

  @type t :: %__MODULE__{
          actor: %{required(String.t()) => String.t()},
          decision: atom(),
          reason: String.t() | nil,
          decided_at: DateTime.t(),
          subject: subject(),
          policy: map() | String.t() | nil,
          admin_mode: boolean(),
          separated_from: [String.t()]
        }

  @doc """
  Called by each path that projects its decisions for Org Audit and Admin Audit (design §4): the
  decisions it holds for an organization, as records.
  """
  @callback decisions(organization_id :: String.t(), opts :: keyword()) :: [t()]

  @doc "The pure decision tables (append-only; the guard test reads this list)."
  @spec tables() :: [String.t()]
  def tables, do: @tables

  @doc "The decisions a record may carry."
  @spec decisions() :: [atom()]
  def decisions, do: @decisions

  @doc """
  Builds and validates a record for `scope`'s decision. `attrs`: `decision`, `subject`, and
  optionally `reason`, `policy`, `separated_from`, `decided_at`. An `actor` or `admin_mode` in
  `attrs` is refused: both come only from the scope.
  """
  @spec new(Scope.t(), map()) :: {:ok, t()} | {:error, term()}
  def new(%Scope{} = scope, attrs) when is_map(attrs) do
    with :ok <- scope_only(attrs),
         {:ok, actor} <- actor(scope),
         {:ok, decision} <- decision(Map.get(attrs, :decision)),
         {:ok, reason} <- reason(decision, Map.get(attrs, :reason)),
         {:ok, subject} <- subject(decision, Map.get(attrs, :subject)),
         {:ok, separated_from} <- separated_from(Map.get(attrs, :separated_from, [])) do
      {:ok,
       %__MODULE__{
         actor: actor,
         decision: decision,
         reason: reason,
         decided_at: Map.get_lazy(attrs, :decided_at, &DateTime.utc_now/0),
         subject: subject,
         policy: Map.get(attrs, :policy),
         admin_mode: scope.admin_mode? == true,
         separated_from: separated_from
       }}
    end
  end

  defp scope_only(attrs) do
    case Enum.find([:actor, :admin_mode], &Map.has_key?(attrs, &1)) do
      nil -> :ok
      key -> {:error, {:decision_record_field_from_scope, key}}
    end
  end

  defp actor(%Scope{} = scope) do
    case Scope.audit_actor(scope) do
      %{"id" => id} = actor when is_binary(id) and id != "" -> {:ok, actor}
      _none -> {:error, :decision_record_actor_required}
    end
  rescue
    _no_actor -> {:error, :decision_record_actor_required}
  end

  defp decision(decision) when decision in @decisions, do: {:ok, decision}
  defp decision(_other), do: {:error, :decision_record_decision_invalid}

  defp reason(decision, reason) do
    case {decision in @reason_required, present(reason)} do
      {true, nil} -> {:error, :decision_record_reason_required}
      {_required, text} -> {:ok, text}
    end
  end

  defp present(reason) when is_binary(reason) do
    case String.trim(reason) do
      "" -> nil
      text -> text
    end
  end

  defp present(_reason), do: nil

  defp subject(decision, %{kind: kind, id: id} = subject)
       when is_binary(kind) and kind != "" and is_binary(id) and id != "" do
    cond do
      decision in @digest_required and not text?(Map.get(subject, :digest)) ->
        {:error, :decision_record_digest_required}

      not optional_text?(Map.get(subject, :previous_digest)) ->
        {:error, :decision_record_previous_digest_invalid}

      true ->
        {:ok, Map.merge(%{version: nil, digest: nil, previous_digest: nil}, subject)}
    end
  end

  defp subject(_decision, _subject), do: {:error, :decision_record_subject_required}

  defp text?(value), do: is_binary(value) and value != ""
  defp optional_text?(value), do: is_nil(value) or text?(value)

  defp separated_from(ids) when is_list(ids) do
    if Enum.all?(ids, &(is_binary(&1) and &1 != "")),
      do: {:ok, Enum.uniq(ids)},
      else: {:error, :decision_record_separated_from_invalid}
  end

  defp separated_from(_ids), do: {:error, :decision_record_separated_from_invalid}
end
