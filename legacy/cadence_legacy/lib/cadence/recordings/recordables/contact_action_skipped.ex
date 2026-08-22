defmodule Cadence.Recordings.Recordables.ContactActionSkipped do
  @moduledoc """
  Recordable for when a contact action is skipped.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "contact_action_skippeds" do
    field :mission_id, :binary_id
    field :contact_id, :binary_id
    field :contact_action_id, :binary_id
    field :reason, :string
    field :details, :map, default: %{}

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @required_fields [:mission_id, :contact_id, :contact_action_id, :reason]
  @optional_fields [:details]

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end

defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.ContactActionSkipped do
  def recording_type(_), do: "ContactActionSkipped"
  def aggregate_type(_), do: "ContactAction"
  def title(_), do: "Contact Action Skipped"
  def status(_), do: "skipped"
  def severity(_), do: nil
end
