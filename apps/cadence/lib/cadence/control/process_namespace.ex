defmodule Cadence.Control.ProcessNamespace do
  @moduledoc """
  Explicit process addresses owned by one Control supervision root.

  Callers provide existing atoms so constructing a namespace never creates
  atoms dynamically. The default value preserves Cadence's production process
  names.
  """

  @enforce_keys [
    :root_supervisor,
    :registry,
    :mission_supervisor,
    :mission_recovery,
    :contact_fact_consumer,
    :runtime_fact_consumer
  ]
  defstruct [
    :root_supervisor,
    :registry,
    :mission_supervisor,
    :mission_recovery,
    :contact_fact_consumer,
    :runtime_fact_consumer
  ]

  @type t :: %__MODULE__{
          root_supervisor: atom(),
          registry: atom(),
          mission_supervisor: atom(),
          mission_recovery: atom(),
          contact_fact_consumer: atom(),
          runtime_fact_consumer: atom()
        }

  @spec default() :: t()
  def default do
    %__MODULE__{
      root_supervisor: Cadence.Control.Supervisor,
      registry: Cadence.Control.Registry,
      mission_supervisor: Cadence.Control.MissionSupervisor,
      mission_recovery: Cadence.Control.MissionRecovery,
      contact_fact_consumer: Cadence.Control.ContactFactConsumer,
      runtime_fact_consumer: Cadence.Control.RuntimeFactConsumer
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
