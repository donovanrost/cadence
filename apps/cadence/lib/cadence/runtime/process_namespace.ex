defmodule Cadence.Runtime.ProcessNamespace do
  @moduledoc """
  Explicit process addresses owned by one Runtime supervision root.

  Callers provide existing atoms so constructing a namespace never creates
  atoms dynamically. The default value preserves Cadence's production process
  names.
  """

  @enforce_keys [:root_supervisor, :registry, :mission_supervisor, :capability_registry]
  defstruct [:root_supervisor, :registry, :mission_supervisor, :capability_registry]

  @type t :: %__MODULE__{
          root_supervisor: atom(),
          registry: atom(),
          mission_supervisor: atom(),
          capability_registry: atom()
        }

  @spec default() :: t()
  def default do
    %__MODULE__{
      root_supervisor: Cadence.Runtime.Supervisor,
      registry: Cadence.Runtime.Registry,
      mission_supervisor: Cadence.Runtime.MissionSupervisor,
      capability_registry: Cadence.Runtime.CapabilityRegistry
    }
  end

  @spec new!(keyword() | map()) :: t()
  def new!(attributes) when is_list(attributes) or is_map(attributes) do
    namespace = struct!(__MODULE__, attributes)

    Enum.each(Map.from_struct(namespace), fn
      {_field, value} when is_atom(value) ->
        :ok

      {field, value} ->
        raise ArgumentError, "#{field} must be an existing atom, got: #{inspect(value)}"
    end)

    namespace
  end

  @spec via(t(), term()) :: {:via, Registry, {atom(), term()}}
  def via(%__MODULE__{registry: registry}, key), do: {:via, Registry, {registry, key}}
end
