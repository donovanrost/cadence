defmodule Cadence.Catalog.ConfigurationReviews.MemberRow do
  @moduledoc "One spacecraft's reviewed configuration version and token within a review."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key false
  schema "spacecraft_configuration_review_members" do
    field(:mission_id, :string, primary_key: true)
    field(:review_sha256, :string, primary_key: true)
    field(:spacecraft_id, :string, primary_key: true)
    field(:organization_id, :string)
    field(:configuration_revision_id, :string)
    field(:configuration_token, :string)
  end
end
