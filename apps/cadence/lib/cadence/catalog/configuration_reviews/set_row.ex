defmodule Cadence.Catalog.ConfigurationReviews.SetRow do
  @moduledoc "A content-addressed configuration review (activation metadata points at it by hash)."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key false
  schema "spacecraft_configuration_reviews" do
    field(:mission_id, :string, primary_key: true)
    field(:review_sha256, :string, primary_key: true)
    field(:organization_id, :string)
    field(:spacecraft_count, :integer)
    field(:inserted_at, :utc_datetime_usec)
  end
end
