defmodule Cadence.ContactPlanning.AutomationGrant do
  @moduledoc """
  The authorization envelope a service identity's automation runs under. #283 (ux U105): under
  'independent' a grant is `proposed` and authorizes nothing until a second org admin approves it;
  under 'direct' it is `active` at once. Validity starts at approval: a proposal carries
  `validity_seconds`, and approval sets `valid_from`/`valid_until`.

  States: proposed, active, rejected, revoked, withdrawn. `expired` is derived on read
  (`effective_state/2`), never stored: an undecided proposal past `proposal_expires_at`, or an
  active grant past `valid_until`.

  The content hash (`content_document/1`) covers what is approved and must not move between
  proposal and approval, so it carries `validity_seconds`, not the approval-time timestamps.
  DECISIONS #108: this layout replaced one with `valid_from`/`valid_until` (#283); a row hashed
  the old way no longer matches `content_sha256/1` and is refused at use
  (`AutomationGrants.authorize/6`), never trusted. The dev reset recreates grants (#112).
  """

  alias Cadence.ContactPlanning.ContentHash
  alias Cadence.Ids
  alias Cadence.Persistence.JsonDocument

  @actions [:plan, :repair, :submit, :approve, :execute]
  @states [:proposed, :active, :rejected, :revoked, :withdrawn]
  @proposal_window_seconds 72 * 3600

  @type action :: :plan | :repair | :submit | :approve | :execute

  @typedoc """
  How a grant ended, for a rejected, withdrawn or revoked one (the state says which): who, when,
  and the reason (required to reject, optional to revoke, the server's own to withdraw).
  """
  @type ending :: %{by: binary(), at: DateTime.t(), reason: binary() | nil}

  @type t :: %__MODULE__{
          automation_grant_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          service_identity_id: binary(),
          fleet_planning_policy_id: binary(),
          fleet_planning_policy_version: pos_integer(),
          allowed_actions: [action()],
          maximum_horizon_seconds: pos_integer(),
          maximum_contacts: pos_integer(),
          maximum_estimated_cost_micros: non_neg_integer() | nil,
          currency: binary() | nil,
          maximum_execution_concurrency: pos_integer(),
          validity_seconds: pos_integer(),
          valid_from: DateTime.t() | nil,
          valid_until: DateTime.t() | nil,
          lifecycle_state: :proposed | :active | :rejected | :revoked | :withdrawn,
          proposed_by: binary(),
          proposed_at: DateTime.t(),
          proposal_expires_at: DateTime.t(),
          approved_by: binary() | nil,
          approved_at: DateTime.t() | nil,
          approval_reason: binary(),
          approval_policy: map() | nil,
          ending: ending() | nil,
          replaces_grant_id: binary() | nil,
          legacy_issue: boolean(),
          content_sha256: binary(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defstruct [
    :automation_grant_id,
    :organization_id,
    :mission_id,
    :service_identity_id,
    :fleet_planning_policy_id,
    :fleet_planning_policy_version,
    :allowed_actions,
    :maximum_horizon_seconds,
    :maximum_contacts,
    :maximum_estimated_cost_micros,
    :currency,
    :maximum_execution_concurrency,
    :validity_seconds,
    :valid_from,
    :valid_until,
    :lifecycle_state,
    :proposed_by,
    :proposed_at,
    :proposal_expires_at,
    :approved_by,
    :approved_at,
    :approval_reason,
    :approval_policy,
    :ending,
    :replaces_grant_id,
    :content_sha256,
    :inserted_at,
    :updated_at,
    legacy_issue: false
  ]

  @spec actions() :: [action()]
  def actions, do: @actions

  @doc "How long a proposal waits for a decision before it expires (72 h, ux U105)."
  @spec proposal_window_seconds() :: pos_integer()
  def proposal_window_seconds, do: @proposal_window_seconds

  @doc """
  The state a reader and `authorize` both see at `now` (ca-security: one function for both):
  the stored state, or `:expired` for an undecided proposal past its window or an active grant
  past `valid_until`. An active grant without approval evidence reads as `:invalid` (fails
  closed).
  """
  @spec effective_state(t(), DateTime.t()) :: atom()
  def effective_state(%__MODULE__{lifecycle_state: :proposed} = grant, now) do
    if DateTime.before?(now, grant.proposal_expires_at), do: :proposed, else: :expired
  end

  def effective_state(%__MODULE__{lifecycle_state: :active} = grant, now) do
    cond do
      is_nil(grant.approved_at) or is_nil(grant.valid_from) or is_nil(grant.valid_until) ->
        :invalid

      not DateTime.before?(now, grant.valid_until) ->
        :expired

      true ->
        :active
    end
  end

  def effective_state(%__MODULE__{lifecycle_state: state}, _now), do: state

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    grant =
      %__MODULE__{
        automation_grant_id: value(attrs, :automation_grant_id, Ids.new("automation_grant")),
        organization_id: required(attrs, :organization_id),
        mission_id: required(attrs, :mission_id),
        service_identity_id: required(attrs, :service_identity_id),
        fleet_planning_policy_id: required(attrs, :fleet_planning_policy_id),
        fleet_planning_policy_version:
          positive(
            value(attrs, :fleet_planning_policy_version),
            :fleet_planning_policy_version
          ),
        allowed_actions: actions(value(attrs, :allowed_actions)),
        maximum_horizon_seconds:
          positive(value(attrs, :maximum_horizon_seconds), :maximum_horizon_seconds),
        maximum_contacts: positive(value(attrs, :maximum_contacts), :maximum_contacts),
        maximum_estimated_cost_micros:
          optional_non_negative(
            value(attrs, :maximum_estimated_cost_micros),
            :maximum_estimated_cost_micros
          ),
        currency: currency(value(attrs, :currency)),
        maximum_execution_concurrency:
          positive(
            value(attrs, :maximum_execution_concurrency),
            :maximum_execution_concurrency
          ),
        validity_seconds: positive(value(attrs, :validity_seconds), :validity_seconds),
        valid_from: optional_datetime(value(attrs, :valid_from), :valid_from),
        valid_until: optional_datetime(value(attrs, :valid_until), :valid_until),
        lifecycle_state:
          attrs
          |> value(:lifecycle_state, :proposed)
          |> atom(@states, :lifecycle_state),
        proposed_by: required(attrs, :proposed_by),
        proposed_at: datetime(value(attrs, :proposed_at), :proposed_at),
        proposal_expires_at: datetime(value(attrs, :proposal_expires_at), :proposal_expires_at),
        approved_by: optional_string(value(attrs, :approved_by)),
        approved_at: optional_datetime(value(attrs, :approved_at), :approved_at),
        approval_reason: required(attrs, :approval_reason),
        approval_policy: value(attrs, :approval_policy),
        ending: ending(value(attrs, :ending)),
        replaces_grant_id: optional_string(value(attrs, :replaces_grant_id)),
        # Issued before #283 (lead 11-19): its proposal fields were filled from its approval.
        legacy_issue: value(attrs, :legacy_issue, false) == true,
        content_sha256: value(attrs, :content_sha256),
        inserted_at: value(attrs, :inserted_at),
        updated_at: value(attrs, :updated_at)
      }
      |> validate_validity()
      |> validate_cost_currency()
      |> validate_revocation_shape()

    %{grant | content_sha256: grant.content_sha256 || content_sha256(grant)}
  end

  @spec content_document(t()) :: map()
  def content_document(%__MODULE__{} = grant) do
    %{
      "organization_id" => grant.organization_id,
      "mission_id" => grant.mission_id,
      "service_identity_id" => grant.service_identity_id,
      "fleet_planning_policy_id" => grant.fleet_planning_policy_id,
      "fleet_planning_policy_version" => grant.fleet_planning_policy_version,
      "allowed_actions" => Enum.map(grant.allowed_actions, &Atom.to_string/1),
      "maximum_horizon_seconds" => grant.maximum_horizon_seconds,
      "maximum_contacts" => grant.maximum_contacts,
      "maximum_estimated_cost_micros" => grant.maximum_estimated_cost_micros,
      "currency" => grant.currency,
      "maximum_execution_concurrency" => grant.maximum_execution_concurrency,
      "validity_seconds" => grant.validity_seconds
    }
  end

  @spec content_sha256(t()) :: binary()
  def content_sha256(%__MODULE__{} = grant),
    do: grant |> content_document() |> JsonDocument.encode() |> ContentHash.sha256()

  # Validity starts at approval: a proposal has no window yet; an approved grant's window is
  # exactly validity_seconds long, from its approval.
  defp validate_validity(%__MODULE__{valid_from: nil, valid_until: nil} = grant), do: grant

  # #506: a grant issued before #283 had its validity_seconds filled from its window by the
  # migration, rounded down to whole seconds, so only the window's order is checked. It's never
  # usable anyway (its hash is the old layout) and is revoke-only.
  defp validate_validity(
         %__MODULE__{legacy_issue: true, valid_from: %DateTime{}, valid_until: %DateTime{}} =
           grant
       ) do
    if DateTime.before?(grant.valid_from, grant.valid_until),
      do: grant,
      else: raise(ArgumentError, "automation grant valid_until must be after valid_from")
  end

  defp validate_validity(%__MODULE__{valid_from: %DateTime{}, valid_until: %DateTime{}} = grant) do
    if DateTime.diff(grant.valid_until, grant.valid_from, :microsecond) ==
         grant.validity_seconds * 1_000_000,
       do: grant,
       else: raise(ArgumentError, "automation grant validity must be validity_seconds long")
  end

  defp validate_validity(_grant),
    do: raise(ArgumentError, "automation grant valid_from and valid_until are set together")

  defp validate_cost_currency(
         %__MODULE__{
           maximum_estimated_cost_micros: nil,
           currency: nil
         } = grant
       ),
       do: grant

  defp validate_cost_currency(
         %__MODULE__{
           maximum_estimated_cost_micros: cost,
           currency: currency
         } = grant
       )
       when is_integer(cost) and is_binary(currency),
       do: grant

  defp validate_cost_currency(_grant),
    do: raise(ArgumentError, "automation grant cost and currency must be set together")

  # Each state carries exactly its own evidence (ca-security: an active grant without approval
  # evidence fails closed, here at construction as well as at use).
  defp validate_revocation_shape(%__MODULE__{lifecycle_state: state} = grant) do
    if shape?(state, approved?(grant), not is_nil(grant.valid_from), grant.ending),
      do: grant,
      else: raise(ArgumentError, "automation grant evidence doesn't match #{state}")
  end

  defp approved?(grant), do: not is_nil(grant.approved_by) and not is_nil(grant.approved_at)

  defp shape?(:proposed, approved, windowed, ending),
    do: not approved and not windowed and is_nil(ending)

  defp shape?(:active, approved, windowed, ending), do: approved and windowed and is_nil(ending)

  # A revoke's reason is recorded when given, never required (a tightening).
  defp shape?(:revoked, approved, windowed, ending),
    do: approved and windowed and not is_nil(ending)

  defp shape?(:rejected, approved, _windowed, ending),
    do: not approved and not is_nil(ending) and present?(ending.reason)

  defp shape?(:withdrawn, approved, _windowed, ending), do: not approved and not is_nil(ending)

  defp present?(text), do: is_binary(text) and String.trim(text) != ""

  defp ending(nil), do: nil

  defp ending(%{by: by, at: at} = ending) when is_binary(by) and by != "",
    do: %{by: by, at: datetime(at, :ending_at), reason: optional_reason(Map.get(ending, :reason))}

  defp ending(_ending), do: raise(ArgumentError, "a grant's ending needs who and when")

  defp optional_reason(reason) when is_binary(reason) do
    case String.trim(reason) do
      "" -> nil
      text -> text
    end
  end

  defp optional_reason(_reason), do: nil

  defp actions(items) when is_list(items) and items != [] do
    normalized =
      items
      |> Enum.map(&atom(&1, @actions, :allowed_actions))
      |> Enum.uniq()
      |> Enum.sort()

    if length(normalized) == length(items),
      do: normalized,
      else: raise(ArgumentError, "automation grant actions must be unique")
  end

  defp actions(_items), do: raise(ArgumentError, "automation grant requires allowed actions")

  defp required(attrs, key) do
    case value(attrs, key) do
      item when is_binary(item) and item != "" -> item
      _other -> raise ArgumentError, "#{key} is required"
    end
  end

  defp positive(value, _field) when is_integer(value) and value > 0, do: value
  defp positive(_value, field), do: raise(ArgumentError, "#{field} must be positive")

  defp optional_non_negative(nil, _field), do: nil

  defp optional_non_negative(value, _field) when is_integer(value) and value >= 0,
    do: value

  defp optional_non_negative(_value, field),
    do: raise(ArgumentError, "#{field} must not be negative")

  defp currency(nil), do: nil
  defp currency(value) when is_binary(value) and value != "", do: String.upcase(value)
  defp currency(_value), do: raise(ArgumentError, "currency must be an ISO-style code")

  defp optional_string(nil), do: nil
  defp optional_string(value) when is_binary(value) and value != "", do: value
  defp optional_string(_value), do: raise(ArgumentError, "optional actor must be non-empty")

  defp datetime(%DateTime{} = value, _field), do: DateTime.truncate(value, :microsecond)
  defp datetime(_value, field), do: raise(ArgumentError, "#{field} must be a timestamp")
  defp optional_datetime(nil, _field), do: nil
  defp optional_datetime(value, field), do: datetime(value, field)

  defp atom(value, allowed, field) when is_atom(value) do
    if value in allowed,
      do: value,
      else: raise(ArgumentError, "unsupported #{field}: #{inspect(value)}")
  end

  defp atom(value, allowed, field) when is_binary(value) do
    Enum.find(allowed, &(Atom.to_string(&1) == value)) ||
      raise ArgumentError, "unsupported #{field}: #{inspect(value)}"
  end

  defp atom(value, _allowed, field),
    do: raise(ArgumentError, "unsupported #{field}: #{inspect(value)}")

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
