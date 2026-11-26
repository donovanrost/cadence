defmodule Cadence.Repo.Migrations.DefineSourceEndpointIdentity do
  use Ecto.Migration

  def change do
    drop(
      unique_index(:mission_source_endpoints, [:mission_id, :source_endpoint_id],
        name: :mission_source_endpoints_scope_idx
      )
    )

    create(
      unique_index(
        :mission_source_endpoints,
        [:mission_id, "COALESCE(spacecraft_id, '')", :source_ref],
        name: :mission_source_endpoints_reference_idx,
        where: "source_ref IS NOT NULL"
      )
    )
  end
end
