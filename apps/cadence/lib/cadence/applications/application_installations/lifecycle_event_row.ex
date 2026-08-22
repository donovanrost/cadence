defmodule Cadence.Applications.ApplicationInstallations.LifecycleEventRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Applications.ApplicationInstallation.LifecycleEvent
  alias Cadence.Persistence.JsonDocument

  @primary_key {:application_installation_event_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "application_installation_events" do
    field(:application_installation_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:scope_kind, :string)
    field(:scope_id, :string)
    field(:application_key, :string)
    field(:event_type, :string)
    field(:previous_lifecycle_state, :string)
    field(:current_lifecycle_state, :string)
    field(:previous_application_version, :integer)
    field(:current_application_version, :integer)
    field(:previous_configuration_version, :integer)
    field(:current_configuration_version, :integer)
    field(:actor_id, :string)
    field(:occurred_at, :utc_datetime_usec)
    field(:payload, :map, default: %{})

    timestamps(updated_at: false)
  end

  @fields [
    :application_installation_event_id,
    :application_installation_id,
    :organization_id,
    :mission_id,
    :scope_kind,
    :scope_id,
    :application_key,
    :event_type,
    :previous_lifecycle_state,
    :current_lifecycle_state,
    :previous_application_version,
    :current_application_version,
    :previous_configuration_version,
    :current_configuration_version,
    :actor_id,
    :occurred_at,
    :payload
  ]

  @required_fields @fields --
                     [
                       :previous_lifecycle_state,
                       :previous_application_version,
                       :previous_configuration_version,
                       :current_configuration_version
                     ]

  @event_types ~w(installed reinstalled enabled disabled uninstalled application_upgraded configuration_updated)
  @lifecycle_states ~w(installed disabled uninstalled)

  @spec changeset(LifecycleEvent.t()) :: Ecto.Changeset.t()
  def changeset(%LifecycleEvent{} = event) do
    %__MODULE__{}
    |> cast(domain_attrs(event), @fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:scope_kind, ["mission", "spacecraft"])
    |> validate_inclusion(:event_type, @event_types)
    |> validate_inclusion(:previous_lifecycle_state, @lifecycle_states)
    |> validate_inclusion(:current_lifecycle_state, @lifecycle_states)
    |> unique_constraint([:application_installation_event_id],
      name: :application_installation_events_pkey
    )
  end

  @spec to_domain(struct()) :: LifecycleEvent.t()
  def to_domain(%__MODULE__{} = row) do
    LifecycleEvent.new(%{
      application_installation_event_id: row.application_installation_event_id,
      application_installation_id: row.application_installation_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      scope_kind: String.to_existing_atom(row.scope_kind),
      scope_id: row.scope_id,
      application_key: row.application_key,
      event_type: String.to_existing_atom(row.event_type),
      previous_lifecycle_state: maybe_existing_atom(row.previous_lifecycle_state),
      current_lifecycle_state: String.to_existing_atom(row.current_lifecycle_state),
      previous_application_version: row.previous_application_version,
      current_application_version: row.current_application_version,
      previous_configuration_version: row.previous_configuration_version,
      current_configuration_version: row.current_configuration_version,
      actor_id: row.actor_id,
      occurred_at: row.occurred_at,
      payload: JsonDocument.unwrap_value(row.payload)
    })
  end

  defp domain_attrs(%LifecycleEvent{} = event) do
    event
    |> Map.from_struct()
    |> Map.update!(:scope_kind, &Atom.to_string/1)
    |> Map.update!(:event_type, &Atom.to_string/1)
    |> Map.update!(:previous_lifecycle_state, &maybe_string/1)
    |> Map.update!(:current_lifecycle_state, &Atom.to_string/1)
    |> Map.update!(:payload, &JsonDocument.wrap_value/1)
  end

  defp maybe_string(nil), do: nil
  defp maybe_string(value), do: Atom.to_string(value)

  defp maybe_existing_atom(nil), do: nil
  defp maybe_existing_atom(value), do: String.to_existing_atom(value)
end
