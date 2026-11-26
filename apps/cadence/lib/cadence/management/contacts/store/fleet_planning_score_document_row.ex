defmodule Cadence.Management.Contacts.Store.FleetPlanningScoreDocumentRow do
  @moduledoc false

  use Ecto.Schema

  alias Cadence.Persistence.JsonDocument

  @primary_key false

  schema "fleet_planning_score_documents" do
    field(:organization_id, :string)
    field(:mission_id, :string, primary_key: true)
    field(:score_document_sha256, :string, primary_key: true)
    field(:score_document, :map)
  end

  def insert_attrs(document, sha256, organization_id, mission_id) do
    %{
      organization_id: organization_id,
      mission_id: mission_id,
      score_document_sha256: sha256,
      score_document: JsonDocument.wrap_value(document)
    }
  end
end
