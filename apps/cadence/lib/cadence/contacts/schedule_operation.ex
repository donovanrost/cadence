defmodule Cadence.Contacts.ScheduleOperation do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:operation_id, :binary_id, autogenerate: false}
  schema "contact_schedule_operations" do
    field(:organization_id, :string)
    field(:user_id, :string)
    field(:mission_id, :string)
    field(:action, :string)
    field(:input, :map)
    field(:reservation_id, :string)
    field(:status, :string, default: "accepted")
    field(:revision, :integer, default: 1)
    field(:result, :map)
    field(:admin_mode, :boolean, default: false)
    timestamps(type: :utc_datetime_usec)
  end
end
