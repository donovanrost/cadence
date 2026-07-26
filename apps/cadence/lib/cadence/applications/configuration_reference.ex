defmodule Cadence.Applications.ConfigurationReference do
  @moduledoc "Versioned reference to configuration owned by an application's domain."

  @type t :: %__MODULE__{
          kind: binary(),
          id: binary(),
          version: pos_integer()
        }

  @enforce_keys [:kind, :id, :version]
  defstruct [:kind, :id, :version]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      kind: fetch_attr!(attrs, :kind),
      id: fetch_attr!(attrs, :id),
      version: fetch_attr!(attrs, :version)
    }
  end

  defp fetch_attr!(attrs, key) do
    Map.get(attrs, key) || Map.fetch!(attrs, Atom.to_string(key))
  end
end
