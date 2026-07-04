defmodule Cadence.Dashboards.DataBinding do
  @moduledoc """
  Mission/realm/logical-source mapping to a physical dashboard data source.
  """

  @type status :: :active | :disabled | :superseded

  @type t :: %__MODULE__{
          binding_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary() | nil,
          realm: atom() | binary(),
          logical_source: atom(),
          data_source_id: binary(),
          dataset: binary() | nil,
          priority: integer(),
          status: status(),
          binding_version: pos_integer(),
          current_event_id: binary() | nil,
          active_from: DateTime.t() | nil,
          active_to: DateTime.t() | nil,
          disabled_at: DateTime.t() | nil,
          superseded_at: DateTime.t() | nil,
          metadata: map()
        }

  defstruct [
    :binding_id,
    :organization_id,
    :mission_id,
    :realm,
    :logical_source,
    :data_source_id,
    :dataset,
    :active_from,
    :active_to,
    :current_event_id,
    :disabled_at,
    :superseded_at,
    priority: 0,
    status: :active,
    binding_version: 1,
    metadata: %{}
  ]

  @spec active?(t()) :: boolean()
  def active?(%__MODULE__{status: :active}), do: true
  def active?(%__MODULE__{}), do: false
end
