defmodule Cadence.Dashboards.DocumentStore.LifecycleEventRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Dashboards.LifecycleEvent
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope

  @primary_key false
  @timestamps_opts [type: :utc_datetime_usec]

  schema "dashboard_lifecycle_events" do
    field(:dashboard_lifecycle_event_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:dashboard_id, :string)
    field(:event_type, :string)
    field(:dashboard_version, :integer)
    field(:previous_lifecycle_state, :string)
    field(:current_lifecycle_state, :string)
    field(:previous_published_version, :integer)
    field(:current_published_version, :integer)
    field(:actor_id, :string)
    field(:occurred_at, :utc_datetime_usec)
    field(:payload, :map, default: %{})

    timestamps(updated_at: false)
  end

  @required_fields [
    :dashboard_lifecycle_event_id,
    :mission_id,
    :dashboard_id,
    :event_type,
    :occurred_at,
    :payload
  ]

  @spec changeset(LifecycleEvent.t()) :: Ecto.Changeset.t()
  def changeset(%LifecycleEvent{} = event) do
    %__MODULE__{}
    |> cast(domain_attrs(event), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> validate_inclusion(:event_type, [
      "published",
      "archived",
      "restored",
      "reverted",
      "comparison_review_requested",
      "comparison_review_resolved",
      "health_snapshot_captured",
      "publish_readiness_checked"
    ])
    |> validate_inclusion(:current_lifecycle_state, ["active", "archived"])
    |> validate_inclusion(:previous_lifecycle_state, ["active", "archived"])
    |> unique_constraint([:dashboard_lifecycle_event_id], name: :dashboard_lifecycle_events_pkey)
  end

  @spec to_domain(struct()) :: LifecycleEvent.t()
  def to_domain(%__MODULE__{} = row) do
    LifecycleEvent.new(%{
      dashboard_lifecycle_event_id: row.dashboard_lifecycle_event_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      dashboard_id: row.dashboard_id,
      event_type: row.event_type,
      dashboard_version: row.dashboard_version,
      previous_lifecycle_state: row.previous_lifecycle_state,
      current_lifecycle_state: row.current_lifecycle_state,
      previous_published_version: row.previous_published_version,
      current_published_version: row.current_published_version,
      actor_id: row.actor_id,
      occurred_at: row.occurred_at,
      payload: JsonDocument.unwrap_value(row.payload)
    })
  end

  defp domain_attrs(%LifecycleEvent{} = event) do
    %{
      dashboard_lifecycle_event_id: event.dashboard_lifecycle_event_id,
      organization_id: event.organization_id,
      mission_id: event.mission_id,
      dashboard_id: event.dashboard_id,
      event_type: Atom.to_string(event.event_type),
      dashboard_version: event.dashboard_version,
      previous_lifecycle_state: event.previous_lifecycle_state,
      current_lifecycle_state: event.current_lifecycle_state,
      previous_published_version: event.previous_published_version,
      current_published_version: event.current_published_version,
      actor_id: event.actor_id,
      occurred_at: event.occurred_at,
      payload: JsonDocument.wrap_value(event.payload)
    }
  end

  defp all_fields do
    [
      :dashboard_lifecycle_event_id,
      :organization_id,
      :mission_id,
      :dashboard_id,
      :event_type,
      :dashboard_version,
      :previous_lifecycle_state,
      :current_lifecycle_state,
      :previous_published_version,
      :current_published_version,
      :actor_id,
      :occurred_at,
      :payload
    ]
  end
end
