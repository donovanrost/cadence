defmodule Cadence.Recordings.Recordables.ContactActionCompleted do
  @moduledoc """
  Recordable for when a contact action completes.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "contact_action_completeds" do
    field :mission_id, :binary_id
    field :contact_id, :binary_id
    field :contact_action_id, :binary_id
    field :result, :map, default: %{}

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @required_fields [:mission_id, :contact_id, :contact_action_id]
  @optional_fields [:result]

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end

defimpl Cadence.Recordings.Recordable,
  for: Cadence.Recordings.Recordables.ContactActionCompleted do
  def recording_type(_), do: "ContactActionCompleted"
  def aggregate_type(_), do: "ContactAction"
  def title(_), do: "Contact Action Completed"
  def status(_), do: "completed"
  def severity(_), do: nil
end
