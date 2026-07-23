defmodule Cadence.Management.Activations.ActivationRequestRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Management.Activations.ActivationRequest
  alias Cadence.Persistence.JsonDocument

  @primary_key {:activation_request_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "activation_requests" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:binding_set_id, :string)
    field(:binding_set_version, :integer)
    field(:binding_set_content_sha256, :string)

    field(:change_class, Ecto.Enum,
      values: [
        :observational,
        :mission_data_plane,
        :transport_provider,
        :command_safety,
        :identity_policy
      ]
    )

    field(:state, Ecto.Enum, values: [:approval_pending, :approved, :rejected])
    field(:requester_actor_kind, Ecto.Enum, values: [:user, :service])
    field(:requester_actor_id, :string)
    field(:requester_actor_document, :map, default: %{})
    field(:policy_document, :map, default: %{})
    field(:metadata, :map, default: %{})
    field(:requested_at, :utc_datetime_usec)
    field(:decided_at, :utc_datetime_usec)

    timestamps()
  end

  @fields [
    :activation_request_id,
    :organization_id,
    :mission_id,
    :binding_set_id,
    :binding_set_version,
    :binding_set_content_sha256,
    :change_class,
    :state,
    :requester_actor_kind,
    :requester_actor_id,
    :requester_actor_document,
    :policy_document,
    :metadata,
    :requested_at,
    :decided_at
  ]

  @required_fields @fields -- [:decided_at]

  def changeset(%ActivationRequest{} = request) do
    %__MODULE__{}
    |> cast(domain_attrs(request), @fields)
    |> validate_required(@required_fields)
  end

  def state_changeset(%__MODULE__{} = row, state, decided_at) do
    row
    |> change(state: state, decided_at: decided_at)
    |> validate_required([:state, :decided_at])
  end

  def to_domain(%__MODULE__{} = row) do
    %ActivationRequest{
      activation_request_id: row.activation_request_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      binding_set_id: row.binding_set_id,
      binding_set_version: row.binding_set_version,
      binding_set_content_sha256: row.binding_set_content_sha256,
      change_class: row.change_class,
      state: row.state,
      requester_actor_kind: row.requester_actor_kind,
      requester_actor_id: row.requester_actor_id,
      requester_actor_document: JsonDocument.unwrap_value(row.requester_actor_document),
      policy_document: JsonDocument.unwrap_value(row.policy_document),
      metadata: JsonDocument.unwrap_value(row.metadata),
      requested_at: row.requested_at,
      decided_at: row.decided_at
    }
  end

  defp domain_attrs(request) do
    request
    |> Map.from_struct()
    |> Map.update!(:requester_actor_document, &JsonDocument.wrap_value/1)
    |> Map.update!(:policy_document, &JsonDocument.wrap_value/1)
    |> Map.update!(:metadata, &JsonDocument.wrap_value/1)
  end
end
