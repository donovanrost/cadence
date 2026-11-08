defmodule Cadence.Repo.Migrations.IndexProtocolCheckpointOrder do
  use Ecto.Migration

  def change do
    create(
      index(
        :transport_capability_records,
        ["(metadata->>'resource_id')", "((metadata->>'checkpoint_revision')::bigint)"],
        name: :transport_protocol_checkpoint_order_idx,
        where: "event_kind = 'protocol_checkpoint'"
      )
    )
  end
end
