defmodule Cadence.Management.Contacts.Store.FleetPlanningScoreDocumentRow do
  @moduledoc false

  use Ecto.Schema

  alias Cadence.Persistence.JsonDocument

  @primary_key {:score_document_sha256, :string, autogenerate: false}

  schema "fleet_planning_score_documents" do
    field(:score_document, :map)
  end

  def insert_attrs(document, sha256) do
    %{
      score_document_sha256: sha256,
      score_document: JsonDocument.wrap_value(document)
    }
  end
end
