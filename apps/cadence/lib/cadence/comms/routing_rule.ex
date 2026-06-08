defmodule Cadence.Comms.RoutingRule do
  @moduledoc """
  Mission-owned durable policy for how a spacecraft uses a Transport.

  Routing Rules are setup state. They are not contacts, schedules, or runtime
  links; compatibility path/link records are materialized only for existing
  runtime integrations.
  """

  alias Cadence.Ids

  @type lifecycle_state :: :active | :archived
  @type direction :: :inbound | :outbound | :bidirectional
  @type role :: :primary | :candidate | :contributing

  @type t :: %__MODULE__{
          routing_rule_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          spacecraft_id: binary(),
          lifecycle_state: lifecycle_state(),
          display_name: binary(),
          purpose_label: binary(),
          direction: direction(),
          transport_id: binary(),
          transport_version: pos_integer(),
          provider_path_ref: binary() | nil,
          role: role(),
          enabled?: boolean(),
          materialized_link_assignment_id: binary() | nil,
          metadata: map()
        }

  defstruct [
    :routing_rule_id,
    :organization_id,
    :mission_id,
    :spacecraft_id,
    :lifecycle_state,
    :display_name,
    :purpose_label,
    :direction,
    :transport_id,
    :transport_version,
    :provider_path_ref,
    :role,
    :materialized_link_assignment_id,
    enabled?: true,
    metadata: %{}
  ]

  @directions [:inbound, :outbound, :bidirectional]
  @roles [:primary, :candidate, :contributing]
  @lifecycle_states [:active, :archived]

  @spec directions() :: [direction()]
  def directions, do: @directions

  @spec roles() :: [role()]
  def roles, do: @roles

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      routing_rule_id:
        Map.get(
          attrs,
          :routing_rule_id,
          Map.get(attrs, "routing_rule_id", Ids.new("routing_rule"))
        ),
      organization_id: Map.get(attrs, :organization_id, Map.get(attrs, "organization_id")),
      mission_id: Map.fetch!(attrs, :mission_id),
      spacecraft_id: Map.fetch!(attrs, :spacecraft_id),
      lifecycle_state:
        attrs
        |> Map.get(:lifecycle_state, Map.get(attrs, "lifecycle_state", :active))
        |> normalize_atom(@lifecycle_states, :lifecycle_state),
      display_name: Map.fetch!(attrs, :display_name),
      purpose_label: Map.fetch!(attrs, :purpose_label),
      direction:
        attrs
        |> Map.get(:direction, Map.get(attrs, "direction"))
        |> normalize_atom(@directions, :direction),
      transport_id: Map.fetch!(attrs, :transport_id),
      transport_version: Map.fetch!(attrs, :transport_version),
      provider_path_ref: Map.get(attrs, :provider_path_ref, Map.get(attrs, "provider_path_ref")),
      role:
        attrs
        |> Map.get(:role, Map.get(attrs, "role", :primary))
        |> normalize_atom(@roles, :role),
      enabled?:
        Map.get(attrs, :enabled?, Map.get(attrs, "enabled", Map.get(attrs, :enabled, true))),
      materialized_link_assignment_id:
        Map.get(
          attrs,
          :materialized_link_assignment_id,
          Map.get(attrs, "materialized_link_assignment_id")
        ),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end

  defp normalize_atom(value, allowed, field) when is_atom(value) do
    if value in allowed do
      value
    else
      raise ArgumentError, "unsupported #{field}: #{inspect(value)}"
    end
  end

  defp normalize_atom(value, allowed, field) when is_binary(value) do
    Enum.find(allowed, &(Atom.to_string(&1) == value)) ||
      raise ArgumentError, "unsupported #{field}: #{inspect(value)}"
  end

  defp normalize_atom(value, _allowed, field) do
    raise ArgumentError, "unsupported #{field}: #{inspect(value)}"
  end
end
