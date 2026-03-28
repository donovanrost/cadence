defmodule Cadence.Recordings.Recordables.ContactReady do
  @moduledoc """
  Recordable for when a contact gate becomes satisfied.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "contact_readies" do
    field :mission_id, :binary_id
    field :contact_id, :binary_id
    field :gate, :string
    field :details, :map, default: %{}

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @required_fields [:mission_id, :contact_id, :gate]
  @optional_fields [:details]

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end

defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.ContactReady do
  def recording_type(_), do: "ContactReady"
  def aggregate_type(_), do: "Contact"
  def title(_), do: "Contact Ready"
  def status(_), do: "ready"
  def severity(_), do: nil
end
