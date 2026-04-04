defmodule Cadence.Persistence.Schemas.ReplayDispatchDecisionRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.ApplicationDispatch.DispatchDecision
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Protocol.PacketRecord

  @primary_key {:dispatch_decision_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "replay_dispatch_decisions" do
    field(:replay_run_id, :string)
    field(:evidence_id, :string)
    field(:packet_id, :string)
    field(:binding_set_id, :string)
    field(:binding_set_version, :integer)
    field(:status, :string)
    field(:matched_rule_ids, :map)
    field(:anomalies, :map)

    timestamps()
  end

  @required_fields [
    :dispatch_decision_id,
    :replay_run_id,
    :evidence_id,
    :packet_id,
    :binding_set_id,
    :binding_set_version,
    :status,
    :matched_rule_ids,
    :anomalies
  ]

  @spec changeset(binary(), PacketRecord.t(), DispatchDecision.t()) :: Ecto.Changeset.t()
  def changeset(
        replay_run_id,
        %PacketRecord{} = packet_record,
        %DispatchDecision{} = dispatch_decision
      )
      when is_binary(replay_run_id) do
    %__MODULE__{}
    |> cast(
      %{
        dispatch_decision_id: dispatch_decision.dispatch_decision_id,
        replay_run_id: replay_run_id,
        evidence_id: dispatch_decision.evidence_id,
        packet_id: packet_record.packet_id,
        binding_set_id: dispatch_decision.binding_set_id,
        binding_set_version: dispatch_decision.binding_set_version,
        status: Atom.to_string(dispatch_decision.status),
        matched_rule_ids: JsonDocument.wrap_items(dispatch_decision.matched_rule_ids),
        anomalies: JsonDocument.wrap_items(dispatch_decision.anomalies)
      },
      all_fields()
    )
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:replay_run_id)
    |> foreign_key_constraint(:evidence_id)
  end

  defp all_fields do
    [
      :dispatch_decision_id,
      :replay_run_id,
      :evidence_id,
      :packet_id,
      :binding_set_id,
      :binding_set_version,
      :status,
      :matched_rule_ids,
      :anomalies
    ]
  end
end
