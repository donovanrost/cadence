defmodule Cadence.Catalog.MissionModel.Diagnostic do
  @moduledoc "Stable compiler and target-legalization diagnostic."

  @type severity :: :info | :warning | :error
  @type support :: :exact | :transformed | :preserved | :lossy | :invalid | nil
  @type stage ::
          :source_validation
          | :namespace
          | :composition
          | :reference_resolution
          | :inheritance
          | :graph
          | :semantic_validation
          | :legalization
          | :target_lowering
  @type target :: :telemetry | :algorithm | :monitoring | :command | nil

  @stages [
    :source_validation,
    :namespace,
    :composition,
    :reference_resolution,
    :inheritance,
    :graph,
    :semantic_validation,
    :legalization,
    :target_lowering
  ]

  @type t :: %__MODULE__{
          code: binary(),
          severity: severity(),
          stage: stage(),
          target: target(),
          semantic_id: binary() | nil,
          message: binary(),
          support: support(),
          provenance: term(),
          metadata: map()
        }

  @enforce_keys [:code, :severity, :stage, :message]
  defstruct @enforce_keys ++
              [:target, :semantic_id, :support, :provenance, metadata: %{}]

  @spec new(map()) :: t()
  def new(attrs) do
    %__MODULE__{
      code: value(attrs, :code),
      severity: attrs |> value(:severity) |> normalize(:severity, [:info, :warning, :error]),
      stage: attrs |> value(:stage) |> normalize(:stage, @stages),
      target:
        attrs
        |> value(:target)
        |> normalize_optional(:target, [:telemetry, :algorithm, :monitoring, :command]),
      semantic_id: value(attrs, :semantic_id),
      message: value(attrs, :message),
      support:
        attrs
        |> value(:support)
        |> normalize_optional(:support, [:exact, :transformed, :preserved, :lossy, :invalid]),
      provenance: value(attrs, :provenance),
      metadata: value(attrs, :metadata, %{})
    }
  end

  @spec blocking?(t()) :: boolean()
  def blocking?(%__MODULE__{severity: :error}), do: true
  def blocking?(%__MODULE__{}), do: false

  # Persisted diagnostics must decode before any compiler or lowering module has
  # been loaded. The wire vocabulary belongs here, not in the VM's current atom table.
  defp normalize(value, field, allowed) do
    case Enum.find(allowed, &(value == &1 or value == Atom.to_string(&1))) do
      nil -> raise ArgumentError, "unsupported diagnostic #{field}: #{inspect(value)}"
      atom -> atom
    end
  end

  defp normalize_optional(nil, _field, _allowed), do: nil
  defp normalize_optional(value, field, allowed), do: normalize(value, field, allowed)

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
