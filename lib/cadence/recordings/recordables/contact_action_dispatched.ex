defmodule Cadence.Recordings.Recordables.ContactActionDispatched do
  @moduledoc """
  Recordable for when a contact action is claimed and dispatched.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "contact_action_dispatcheds" do
    field :mission_id, :binary_id
    field :contact_id, :binary_id
    field :contact_action_id, :binary_id
    field :gate, :string
    field :command_ref, :map
    field :details, :map, default: %{}

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @required_fields [:mission_id, :contact_id, :contact_action_id, :gate, :command_ref]
  @optional_fields [:details]

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:contact_action_id)
  end
end

defimpl Cadence.Recordings.Recordable,
  for: Cadence.Recordings.Recordables.ContactActionDispatched do
  def recording_type(_), do: "ContactActionDispatched"
  def aggregate_type(_), do: "ContactAction"
  def title(_), do: "Contact Action Dispatched"
  def status(_), do: "dispatched"
  def severity(_), do: nil
end
