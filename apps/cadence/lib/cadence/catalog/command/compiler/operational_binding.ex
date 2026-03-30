defmodule Cadence.Catalog.Command.Compiler.OperationalBinding do
  @moduledoc """
  Runtime-facing command operational binding used by future approval, release,
  and uplink surfaces.
  """

  @type significance :: :routine | :warning | :critical | :hazardous | nil

  @type t :: %__MODULE__{
          command_id: binary(),
          name: binary(),
          display_name: binary() | nil,
          significance: significance(),
          critical: boolean(),
          hazardous: boolean(),
          subsystem: binary() | nil,
          group_name: binary() | nil,
          preferred_uplink_service: binary() | nil,
          release_policy_hint: binary() | nil,
          apid: non_neg_integer() | nil,
          service_type: non_neg_integer() | nil,
          service_subtype: non_neg_integer() | nil,
          opcode: term() | nil,
          metadata: map()
        }

  defstruct [
    :command_id,
    :name,
    :display_name,
    :significance,
    :subsystem,
    :group_name,
    :preferred_uplink_service,
    :release_policy_hint,
    :apid,
    :service_type,
    :service_subtype,
    :opcode,
    critical: false,
    hazardous: false,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      command_id: Map.fetch!(attrs, :command_id),
      name: Map.fetch!(attrs, :name),
      display_name: Map.get(attrs, :display_name),
      significance: Map.get(attrs, :significance),
      critical: Map.get(attrs, :critical, false),
      hazardous: Map.get(attrs, :hazardous, false),
      subsystem: Map.get(attrs, :subsystem),
      group_name: Map.get(attrs, :group_name),
      preferred_uplink_service: Map.get(attrs, :preferred_uplink_service),
      release_policy_hint: Map.get(attrs, :release_policy_hint),
      apid: Map.get(attrs, :apid),
      service_type: Map.get(attrs, :service_type),
      service_subtype: Map.get(attrs, :service_subtype),
      opcode: Map.get(attrs, :opcode),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end
end
