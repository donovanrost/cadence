defmodule Cadence.Catalog.Command.OperationalMetadata do
  @moduledoc """
  Operator-facing command metadata imported from source command catalogs.
  """

  alias Cadence.Catalog.Command.Normalize

  @type significance :: :routine | :warning | :critical | :hazardous | nil

  @type t :: %__MODULE__{
          significance: significance(),
          critical: boolean(),
          hazardous: boolean(),
          subsystem: binary() | nil,
          group_name: binary() | nil,
          preferred_uplink_service: binary() | nil,
          release_policy_hint: binary() | nil,
          metadata: map(),
          extensions: map()
        }

  defstruct [
    :significance,
    :subsystem,
    :group_name,
    :preferred_uplink_service,
    :release_policy_hint,
    critical: false,
    hazardous: false,
    metadata: %{},
    extensions: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      significance: Normalize.get(attrs, :significance) |> normalize_significance(),
      critical: Normalize.get(attrs, :critical, false),
      hazardous: Normalize.get(attrs, :hazardous, false),
      subsystem: Normalize.get(attrs, :subsystem),
      group_name: Normalize.get(attrs, :group_name),
      preferred_uplink_service: Normalize.get(attrs, :preferred_uplink_service),
      release_policy_hint: Normalize.get(attrs, :release_policy_hint),
      metadata: Normalize.get(attrs, :metadata, %{}),
      extensions: Normalize.get(attrs, :extensions, %{})
    }
  end

  defp normalize_significance(nil), do: nil
  defp normalize_significance(:routine), do: :routine
  defp normalize_significance("routine"), do: :routine
  defp normalize_significance(:warning), do: :warning
  defp normalize_significance("warning"), do: :warning
  defp normalize_significance(:critical), do: :critical
  defp normalize_significance("critical"), do: :critical
  defp normalize_significance(:hazardous), do: :hazardous
  defp normalize_significance("hazardous"), do: :hazardous
  defp normalize_significance(_other), do: nil
end
