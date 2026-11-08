defmodule Cadence.Repo.Migrations.IndexTransportSendPreparations do
  use Ecto.Migration

  def change do
    create(
      index(
        :transport_action_requests,
        ["(metadata->>'resource_id')", "(metadata->>'send_status')"],
        name: :transport_send_resource_status_idx,
        where: "action_kind = 'provider_send_prepared'"
      )
    )

    create(
      unique_index(
        :transport_action_requests,
        ["(metadata->>'resource_id')", "(metadata->>'recovery_operation_id')"],
        name: :transport_send_recovery_operation_idx,
        where:
          "action_kind = 'provider_send_prepared' AND metadata->>'recovery_operation_id' IS NOT NULL"
      )
    )
  end
end
