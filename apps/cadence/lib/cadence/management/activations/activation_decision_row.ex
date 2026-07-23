defmodule Cadence.Management.Activations.ActivationDecisionRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Management.Activations.ActivationDecision
  alias Cadence.Persistence.JsonDocument

  @primary_key {:activation_decision_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "activation_decisions" do
    field(:activation_request_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:decision, Ecto.Enum, values: [:approved, :rejected])
    field(:actor_kind, Ecto.Enum, values: [:user])
    field(:actor_id, :string)
    field(:actor_document, :map, default: %{})
    field(:reason, :string)
    field(:decided_at, :utc_datetime_usec)

    timestamps()
  end

  @fields [
    :activation_decision_id,
    :activation_request_id,
    :organization_id,
    :mission_id,
    :decision,
    :actor_kind,
    :actor_id,
    :actor_document,
    :reason,
    :decided_at
  ]

  def changeset(%ActivationDecision{} = decision) do
    %__MODULE__{}
    |> cast(domain_attrs(decision), @fields)
    |> validate_required(@fields)
  end

  def to_domain(%__MODULE__{} = row) do
    %ActivationDecision{
      activation_decision_id: row.activation_decision_id,
      activation_request_id: row.activation_request_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      decision: row.decision,
      actor_kind: row.actor_kind,
      actor_id: row.actor_id,
      actor_document: JsonDocument.unwrap_value(row.actor_document),
      reason: row.reason,
      decided_at: row.decided_at
    }
  end

  defp domain_attrs(decision) do
    decision
    |> Map.from_struct()
    |> Map.update!(:actor_document, &JsonDocument.wrap_value/1)
  end
end
