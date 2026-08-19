defmodule Cadence.Commanding.ProcessNamespace do
  @moduledoc """
  Explicit process addresses owned by one Commanding supervision root.

  Callers provide existing atoms or registered server names so constructing a
  namespace never creates atoms dynamically. The default value preserves
  Cadence's production process names.
  """

  @enforce_keys [
    :root_supervisor,
    :registry,
    :lane_supervisor,
    :dispatcher,
    :verifier_scheduler
  ]
  defstruct [
    :root_supervisor,
    :registry,
    :lane_supervisor,
    :dispatcher,
    :verifier_scheduler
  ]

  @type registered_name :: atom() | {:global, term()} | {:via, module(), term()}
  @type t :: %__MODULE__{
          root_supervisor: registered_name(),
          registry: atom(),
          lane_supervisor: registered_name(),
          dispatcher: registered_name(),
          verifier_scheduler: registered_name()
        }

  @spec default() :: t()
  def default do
    %__MODULE__{
      root_supervisor: Cadence.Commanding.DispatchSupervisor,
      registry: Cadence.Commanding.DispatchRegistry,
      lane_supervisor: Cadence.Commanding.LaneDispatcherSupervisor,
      dispatcher: Cadence.Commanding.Dispatcher,
      verifier_scheduler: Cadence.Commanding.VerifierScheduler
    }
  end

  @spec new!(keyword() | map()) :: t()
  def new!(attributes) when is_list(attributes) or is_map(attributes) do
    namespace = struct!(__MODULE__, attributes)

    Enum.each(Map.from_struct(namespace), fn
      {:registry, value} when is_atom(value) ->
        :ok

      {:registry, value} ->
        raise ArgumentError, "registry must be an existing atom, got: #{inspect(value)}"

      {_field, value} when is_atom(value) ->
        :ok

      {_field, {:global, _term}} ->
        :ok

      {_field, {:via, module, _term}} when is_atom(module) ->
        :ok

      {field, value} ->
        raise ArgumentError,
              "#{field} must be an existing atom or registered server name, got: #{inspect(value)}"
    end)

    namespace
  end

  @spec via(t(), term()) :: {:via, Registry, {atom(), term()}}
  def via(%__MODULE__{registry: registry}, key), do: {:via, Registry, {registry, key}}
end
