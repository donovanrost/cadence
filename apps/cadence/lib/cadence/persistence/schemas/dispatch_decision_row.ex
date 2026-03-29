defmodule Cadence.Persistence.Schemas.DispatchDecisionRow do
  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.ApplicationDispatch.DispatchDecision
  alias Cadence.Persistence.JsonDocument

  @primary_key {:dispatch_decision_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "application_dispatch_decisions" do
    field(:packet_id, :string)
    field(:evidence_id, :string)
    field(:binding_set_id, :string)
    field(:binding_set_version, :integer)
    field(:status, :string)
    field(:matched_rule_ids, :map)
    field(:anomalies, :map)

    timestamps()
  end

  @required_fields [
    :dispatch_decision_id,
    :packet_id,
    :evidence_id,
    :binding_set_id,
    :binding_set_version,
    :status,
    :matched_rule_ids,
    :anomalies
  ]

  @spec changeset(DispatchDecision.t()) :: Ecto.Changeset.t()
  def changeset(%DispatchDecision{} = dispatch_decision) do
    %__MODULE__{}
    |> cast(row_attrs(dispatch_decision), all_fields())
    |> validate_required(@required_fields)
    |> unique_constraint(:packet_id)
  end

  @spec row_attrs(DispatchDecision.t(), keyword()) :: map()
  def row_attrs(%DispatchDecision{} = dispatch_decision, opts \\ []) do
    inserted_at = Keyword.get(opts, :inserted_at)

    %{
      dispatch_decision_id: dispatch_decision.dispatch_decision_id,
      packet_id: dispatch_decision.packet_id,
      evidence_id: dispatch_decision.evidence_id,
      binding_set_id: dispatch_decision.binding_set_id,
      binding_set_version: dispatch_decision.binding_set_version,
      status: Atom.to_string(dispatch_decision.status),
      matched_rule_ids: JsonDocument.wrap_items(dispatch_decision.matched_rule_ids),
      anomalies: JsonDocument.wrap_items(dispatch_decision.anomalies)
    }
    |> maybe_put_inserted_at(inserted_at)
  end

  defp all_fields do
    [
      :dispatch_decision_id,
      :packet_id,
      :evidence_id,
      :binding_set_id,
      :binding_set_version,
      :status,
      :matched_rule_ids,
      :anomalies
    ]
  end

  defp maybe_put_inserted_at(attrs, nil), do: attrs
  defp maybe_put_inserted_at(attrs, inserted_at), do: Map.put(attrs, :inserted_at, inserted_at)
end
