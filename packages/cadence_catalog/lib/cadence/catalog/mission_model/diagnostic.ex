defmodule Cadence.Catalog.MissionModel.Diagnostic do
  @moduledoc "Stable compiler and target-legalization diagnostic."

  @type severity :: :info | :warning | :error
  @type support :: :exact | :transformed | :preserved | :lossy | :invalid | nil

  @type t :: %__MODULE__{
          code: binary(),
          severity: severity(),
          stage: atom(),
          target: atom() | nil,
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
      severity: attrs |> value(:severity) |> normalize_atom(),
      stage: attrs |> value(:stage) |> normalize_atom(),
      target: attrs |> value(:target) |> normalize_optional_atom(),
      semantic_id: value(attrs, :semantic_id),
      message: value(attrs, :message),
      support: attrs |> value(:support) |> normalize_optional_atom(),
      provenance: value(attrs, :provenance),
      metadata: value(attrs, :metadata, %{})
    }
  end

  @spec blocking?(t()) :: boolean()
  def blocking?(%__MODULE__{severity: :error}), do: true
  def blocking?(%__MODULE__{}), do: false

  defp normalize_atom(value) when is_atom(value), do: value
  defp normalize_atom(value) when is_binary(value), do: String.to_existing_atom(value)

  defp normalize_optional_atom(nil), do: nil
  defp normalize_optional_atom(value), do: normalize_atom(value)

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
