defmodule Cadence.Accounts.AccountEventRow do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:account_event_id, :string, autogenerate: false}

  schema "account_events" do
    field(:user_id, :string)
    field(:actor_id, :string)
    field(:action, :string)
    field(:details, :map, default: %{})
    field(:occurred_at, :utc_datetime_usec)
  end
end
