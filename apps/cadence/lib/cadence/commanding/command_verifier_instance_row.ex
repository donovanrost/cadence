defmodule Cadence.Commanding.CommandVerifierInstanceRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Catalog.Command.MatchCriteria
  alias Cadence.Commanding.CommandVerifierInstance
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope

  @primary_key {:command_verifier_instance_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "command_verifier_instances" do
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:command_request_id, :string)
    field(:command_release_attempt_id, :string)
    field(:source_endpoint_ref, :string)
    field(:command_snapshot_id, :string)
    field(:command_id, :string)
    field(:command_name, :string)
    field(:verifier_id, :string)
    field(:verifier_name, :string)
    field(:phase, :string)
    field(:severity, :string)
    field(:success_criteria_document, :map, default: %{})
    field(:failure_criteria_document, :map, default: %{})
    field(:delay_until, :utc_datetime_usec)
    field(:timeout_at, :utc_datetime_usec)
    field(:lifecycle_state, :string)
    field(:matched_record_kind, :string)
    field(:matched_record_id, :string)
    field(:matched_at, :utc_datetime_usec)
    field(:failure_reason, :string)
    field(:metadata_document, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :command_verifier_instance_id,
    :mission_id,
    :command_request_id,
    :command_release_attempt_id,
    :source_endpoint_ref,
    :command_snapshot_id,
    :command_id,
    :verifier_id,
    :verifier_name,
    :phase,
    :lifecycle_state,
    :metadata_document
  ]

  @spec changeset(CommandVerifierInstance.t()) :: Ecto.Changeset.t()
  def changeset(%CommandVerifierInstance{} = command_verifier_instance) do
    %__MODULE__{}
    |> cast(domain_attrs(command_verifier_instance), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> unique_constraint([:mission_id, :command_verifier_instance_id],
      name: :command_verifier_instances_scope_idx
    )
  end

  @spec update_changeset(struct(), CommandVerifierInstance.t()) :: Ecto.Changeset.t()
  def update_changeset(
        %__MODULE__{} = row,
        %CommandVerifierInstance{} = command_verifier_instance
      ) do
    row
    |> cast(domain_attrs(command_verifier_instance), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
  end

  @spec to_domain(struct()) :: CommandVerifierInstance.t()
  def to_domain(%__MODULE__{} = row) do
    CommandVerifierInstance.new(%{
      command_verifier_instance_id: row.command_verifier_instance_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      command_request_id: row.command_request_id,
      command_release_attempt_id: row.command_release_attempt_id,
      source_endpoint_ref: row.source_endpoint_ref,
      command_snapshot_id: row.command_snapshot_id,
      command_id: row.command_id,
      command_name: row.command_name,
      verifier_id: row.verifier_id,
      verifier_name: row.verifier_name,
      phase: row.phase,
      severity: row.severity,
      success_criteria: unwrap_match_criteria(row.success_criteria_document),
      failure_criteria: unwrap_match_criteria(row.failure_criteria_document),
      delay_until: row.delay_until,
      timeout_at: row.timeout_at,
      lifecycle_state: row.lifecycle_state,
      matched_record_kind: row.matched_record_kind,
      matched_record_id: row.matched_record_id,
      matched_at: row.matched_at,
      failure_reason: row.failure_reason,
      metadata: JsonDocument.unwrap_value(row.metadata_document)
    })
  end

  defp domain_attrs(%CommandVerifierInstance{} = command_verifier_instance) do
    %{
      command_verifier_instance_id: command_verifier_instance.command_verifier_instance_id,
      organization_id: command_verifier_instance.organization_id,
      mission_id: command_verifier_instance.mission_id,
      command_request_id: command_verifier_instance.command_request_id,
      command_release_attempt_id: command_verifier_instance.command_release_attempt_id,
      source_endpoint_ref: command_verifier_instance.source_endpoint_ref,
      command_snapshot_id: command_verifier_instance.command_snapshot_id,
      command_id: command_verifier_instance.command_id,
      command_name: command_verifier_instance.command_name,
      verifier_id: command_verifier_instance.verifier_id,
      verifier_name: command_verifier_instance.verifier_name,
      phase: Atom.to_string(command_verifier_instance.phase),
      severity:
        case command_verifier_instance.severity do
          nil -> nil
          severity -> Atom.to_string(severity)
        end,
      success_criteria_document:
        JsonDocument.wrap_value(command_verifier_instance.success_criteria),
      failure_criteria_document:
        JsonDocument.wrap_value(command_verifier_instance.failure_criteria),
      delay_until: command_verifier_instance.delay_until,
      timeout_at: command_verifier_instance.timeout_at,
      lifecycle_state: Atom.to_string(command_verifier_instance.lifecycle_state),
      matched_record_kind:
        case command_verifier_instance.matched_record_kind do
          nil -> nil
          matched_record_kind -> Atom.to_string(matched_record_kind)
        end,
      matched_record_id: command_verifier_instance.matched_record_id,
      matched_at: command_verifier_instance.matched_at,
      failure_reason: command_verifier_instance.failure_reason,
      metadata_document: JsonDocument.wrap_value(command_verifier_instance.metadata)
    }
  end

  defp all_fields do
    [
      :command_verifier_instance_id,
      :organization_id,
      :mission_id,
      :command_request_id,
      :command_release_attempt_id,
      :source_endpoint_ref,
      :command_snapshot_id,
      :command_id,
      :command_name,
      :verifier_id,
      :verifier_name,
      :phase,
      :severity,
      :success_criteria_document,
      :failure_criteria_document,
      :delay_until,
      :timeout_at,
      :lifecycle_state,
      :matched_record_kind,
      :matched_record_id,
      :matched_at,
      :failure_reason,
      :metadata_document
    ]
  end

  defp unwrap_match_criteria(document) do
    case JsonDocument.unwrap_value(document) do
      nil -> nil
      criteria when is_map(criteria) -> MatchCriteria.new(criteria)
      _other -> nil
    end
  end
end
