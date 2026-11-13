defmodule Cadence.Administration.PlatformEventRow do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:platform_event_id, :string, autogenerate: false}

  schema "platform_events" do
    field(:actor_id, :string)
    field(:action, :string)
    field(:organization_id, :string)
    field(:target_kind, :string)
    field(:target_id, :string)
    field(:target_label, :string)
    field(:details, :map, default: %{})
    field(:occurred_at, :utc_datetime_usec)
  end
end
