defmodule CCSDS.CFDP.FaultPolicy do
  @moduledoc """
  Configurable CFDP fault-handler selection.

  Defaults are caller-owned MIB values. Per-transaction Fault Handler Override
  TLVs take precedence when supplied. This module selects protocol actions but
  does not log faults or persist transaction state.
  """

  alias CCSDS.CFDP
  alias CCSDS.CFDP.TLV.FaultHandlerOverride

  @type handler :: :cancel | :suspend | :ignore | :abandon
  @type t :: %__MODULE__{default_handler: handler(), handlers: %{CFDP.condition() => handler()}}

  defstruct default_handler: :cancel, handlers: %{}

  @handlers [:cancel, :suspend, :ignore, :abandon]
  @non_fault_conditions [:no_error, :suspend_request_received, :cancel_request_received]

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs \\ %{}) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)
    default_handler = Map.get(attrs, :default_handler, :cancel)
    handlers = Map.get(attrs, :handlers, %{})

    with :ok <- validate_handler(default_handler, :default_handler),
         :ok <- validate_handlers(handlers) do
      {:ok, %__MODULE__{default_handler: default_handler, handlers: handlers}}
    end
  end

  @spec new!(map() | keyword()) :: t()
  def new!(attrs \\ %{}) do
    case new(attrs) do
      {:ok, policy} -> policy
      {:error, reason} -> raise ArgumentError, "invalid CFDP fault policy: #{inspect(reason)}"
    end
  end

  @spec handler(t(), CFDP.condition(), list()) :: handler()
  def handler(%__MODULE__{} = policy, condition, options \\ []) when is_list(options) do
    case Enum.find(options, &matches_condition?(&1, condition)) do
      %FaultHandlerOverride{handler: handler} -> handler
      nil -> Map.get(policy.handlers, condition, policy.default_handler)
    end
  end

  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = policy) do
    with :ok <- validate_handler(policy.default_handler, :default_handler) do
      validate_handlers(policy.handlers)
    end
  end

  def validate(value), do: {:error, {:invalid_fault_policy, value}}

  defp validate_handlers(handlers) when is_map(handlers) do
    Enum.reduce_while(handlers, :ok, fn {condition, handler}, :ok ->
      with :ok <- validate_condition(condition),
           :ok <- validate_handler(handler, condition) do
        {:cont, :ok}
      else
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_handlers(value), do: {:error, {:invalid_field, :handlers, value}}

  defp validate_condition(condition) when condition in @non_fault_conditions,
    do: {:error, {:invalid_fault_condition, condition}}

  defp validate_condition(condition) do
    CFDP.condition_code(condition)
    :ok
  rescue
    KeyError -> {:error, {:invalid_fault_condition, condition}}
  end

  defp validate_handler(handler, _field) when handler in @handlers, do: :ok
  defp validate_handler(handler, field), do: {:error, {:invalid_fault_handler, field, handler}}

  defp matches_condition?(%FaultHandlerOverride{condition: condition}, condition), do: true
  defp matches_condition?(_option, _condition), do: false
end
