defmodule Cadence.Commanding.Groups.CommandGroupEventRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Ids
  alias Cadence.Persistence.JsonDocument

  @primary_key {:event_id, :string, autogenerate: false}

  @kinds ~w(submitted approved approved_with_exclusions sent_back rejected note member_canceled
            aborted member_failed completed hold_acknowledged
            released_on_contact expired)

  @doc "The event kinds, as text (the paged events read filters by them)."
  @spec kinds() :: [binary()]
  def kinds, do: @kinds

  schema "command_group_events" do
    field(:command_group_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:kind, :string)
    field(:actor_document, :map)
    field(:at, :utc_datetime_usec)
    field(:payload_document, :map, default: %{})
  end

  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs) do
    %__MODULE__{}
    |> cast(
      %{
        event_id: Map.get(attrs, :event_id) || Ids.new("command_group_event"),
        command_group_id: attrs.command_group_id,
        mission_id: attrs.mission_id,
        kind: to_string(attrs.kind),
        actor_document: attrs[:actor] && JsonDocument.wrap_value(attrs.actor),
        at: Map.get(attrs, :at) || DateTime.utc_now(),
        payload_document: JsonDocument.wrap_value(Map.get(attrs, :payload, %{}))
      },
      __schema__(:fields)
    )
    |> validate_required([:event_id, :command_group_id, :mission_id, :kind, :at])
    |> validate_inclusion(:kind, @kinds)
  end

  @spec to_domain(struct()) :: map()
  def to_domain(%__MODULE__{} = row) do
    %{
      id: row.event_id,
      kind: kind(row.kind),
      actor: row.actor_document && JsonDocument.unwrap_value(row.actor_document),
      at: row.at,
      payload: JsonDocument.unwrap_value(row.payload_document)
    }
  end

  # qa #39: never String.to_existing_atom on stored values. The atoms are made here at compile
  # time from the known kinds, so they exist after a restart; an unknown kind stays a string.
  @kind_atoms Map.new(@kinds, &{&1, String.to_atom(&1)})

  defp kind(kind), do: Map.get(@kind_atoms, kind, kind)
end
