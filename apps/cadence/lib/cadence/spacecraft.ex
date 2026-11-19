defmodule Cadence.Spacecraft do
  @moduledoc """
  Mission-owned spacecraft asset.
  """

  alias Cadence.Ids

  @type t :: %__MODULE__{
          spacecraft_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          display_name: binary(),
          scid: non_neg_integer() | nil,
          spacecraft_type_id: binary() | nil,
          spacecraft_type_version: pos_integer() | nil,
          metadata: map(),
          lifecycle_state: :active | :archived,
          archived_at: DateTime.t() | nil,
          archived_by: map() | nil,
          commanding_enabled: boolean() | nil,
          telemetry_enabled: boolean() | nil
        }

  defstruct [
    :spacecraft_id,
    :organization_id,
    :mission_id,
    :display_name,
    :scid,
    :spacecraft_type_id,
    :spacecraft_type_version,
    :archived_at,
    :archived_by,
    # L22: set by change sets; nil means "as the spacecraft's configuration has it".
    :commanding_enabled,
    :telemetry_enabled,
    metadata: %{},
    lifecycle_state: :active
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      spacecraft_id:
        Map.get(attrs, :spacecraft_id, Map.get(attrs, "spacecraft_id", Ids.new("spacecraft"))),
      organization_id: Map.get(attrs, :organization_id, Map.get(attrs, "organization_id")),
      mission_id: Map.fetch!(attrs, :mission_id),
      display_name: Map.fetch!(attrs, :display_name),
      scid: Map.get(attrs, :scid, Map.get(attrs, "scid")),
      spacecraft_type_id:
        Map.get(attrs, :spacecraft_type_id, Map.get(attrs, "spacecraft_type_id")),
      spacecraft_type_version:
        Map.get(attrs, :spacecraft_type_version, Map.get(attrs, "spacecraft_type_version")),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{})),
      lifecycle_state:
        lifecycle(Map.get(attrs, :lifecycle_state, Map.get(attrs, "lifecycle_state"))),
      archived_at: Map.get(attrs, :archived_at, Map.get(attrs, "archived_at")),
      archived_by: Map.get(attrs, :archived_by, Map.get(attrs, "archived_by")),
      commanding_enabled:
        Map.get(attrs, :commanding_enabled, Map.get(attrs, "commanding_enabled")),
      telemetry_enabled: Map.get(attrs, :telemetry_enabled, Map.get(attrs, "telemetry_enabled"))
    }
  end

  defp lifecycle(state) when state in [:archived, "archived"], do: :archived
  defp lifecycle(_state), do: :active

  @doc "Whether the spacecraft has been archived (#49/#50)."
  @spec archived?(t()) :: boolean()
  def archived?(%__MODULE__{lifecycle_state: state}), do: state == :archived
end
