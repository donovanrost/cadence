defmodule Cadence.Repo.Migrations.IndexProtocolCheckpoints do
  use Ecto.Migration

  def change do
    create(
      unique_index(
        :transport_capability_records,
        ["(metadata->>'resource_id')", "(metadata->>'checkpoint_revision')"],
        name: :transport_protocol_checkpoint_revision_idx,
        where: "event_kind = 'protocol_checkpoint'"
      )
    )
  end
end
