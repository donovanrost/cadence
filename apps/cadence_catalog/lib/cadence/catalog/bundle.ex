defmodule Cadence.Catalog.Bundle do
  @moduledoc """
  Portable canonical output shared by catalog importers and compilers.
  """

  alias Cadence.Catalog.Command.Snapshot, as: CommandSnapshot
  alias Cadence.Catalog.MissionModel.Layer
  alias Cadence.Catalog.Telemetry.Snapshot, as: TelemetrySnapshot

  @type t :: %__MODULE__{
          telemetry_snapshot: TelemetrySnapshot.t() | nil,
          command_snapshot: CommandSnapshot.t() | nil,
          declaration_layers: [Layer.t()],
          metadata: map()
        }

  defstruct [:telemetry_snapshot, :command_snapshot, declaration_layers: [], metadata: %{}]

  @spec new(map()) :: t()
  def new(attrs \\ %{}) when is_map(attrs) do
    %__MODULE__{
      telemetry_snapshot:
        Map.get(attrs, :telemetry_snapshot, Map.get(attrs, "telemetry_snapshot")),
      command_snapshot: Map.get(attrs, :command_snapshot, Map.get(attrs, "command_snapshot")),
      declaration_layers:
        Map.get(attrs, :declaration_layers, Map.get(attrs, "declaration_layers", [])),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end
end
