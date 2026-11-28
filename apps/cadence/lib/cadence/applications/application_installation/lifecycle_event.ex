defmodule Cadence.Applications.ApplicationInstallation.LifecycleEvent do
  @moduledoc "Append-only history for installation lifecycle and application-version changes."

  alias Cadence.Applications.ApplicationInstallation
  alias Cadence.Ids

  @type event_type ::
          :installed
          | :reinstalled
          | :enabled
          | :disabled
          | :uninstalled
          | :application_upgraded

  @type t :: %__MODULE__{
          application_installation_event_id: binary(),
          application_installation_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          scope_kind: :mission | :spacecraft,
          scope_id: binary(),
          application_key: binary(),
          event_type: event_type(),
          previous_lifecycle_state: ApplicationInstallation.lifecycle_state() | nil,
          current_lifecycle_state: ApplicationInstallation.lifecycle_state(),
          previous_application_version: pos_integer() | nil,
          current_application_version: pos_integer(),
          actor_id: binary(),
          occurred_at: DateTime.t(),
          payload: map()
        }

  defstruct [
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
    :actor_id,
    :occurred_at,
    payload: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    struct!(
      __MODULE__,
      Map.put_new(
        attrs,
        :application_installation_event_id,
        Ids.new("application_installation_event")
      )
    )
  end
end
