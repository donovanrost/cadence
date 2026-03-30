defmodule Cadence.Catalog.Diagnostic do
  @moduledoc """
  Structured catalog import diagnostic.
  """

  @type severity :: :info | :warning | :error

  @type t :: %__MODULE__{
          severity: severity(),
          code: binary(),
          message: binary(),
          path: [binary()],
          metadata: map()
        }

  defstruct [:severity, :code, :message, path: [], metadata: %{}]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      severity: attrs |> fetch!(:severity) |> severity(),
      code: fetch!(attrs, :code),
      message: fetch!(attrs, :message),
      path: Map.get(attrs, :path, Map.get(attrs, "path", [])),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end

  defp severity(value) when value in [:info, :warning, :error], do: value
  defp severity("info"), do: :info
  defp severity("warning"), do: :warning
  defp severity("error"), do: :error

  defp fetch!(attrs, key) when is_atom(key) do
    Map.get_lazy(attrs, key, fn -> Map.fetch!(attrs, Atom.to_string(key)) end)
  end
end
