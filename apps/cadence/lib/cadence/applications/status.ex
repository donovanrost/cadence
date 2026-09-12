defmodule Cadence.Applications.Status do
  @moduledoc "Host-standard application status projection used by inventories and shells."

  @type tone :: :ready | :attention | :blocked | :info
  @type fact :: %{id: binary(), label: binary(), value: binary()}

  @type t :: %__MODULE__{
          state: atom(),
          label: binary(),
          tone: tone(),
          facts: [fact()],
          outstanding_actions: [binary()]
        }

  @enforce_keys [:state, :label, :tone]
  defstruct [:state, :label, :tone, facts: [], outstanding_actions: []]

  @spec roadmap() :: t()
  def roadmap do
    %__MODULE__{state: :roadmap, label: "Roadmap", tone: :blocked}
  end

  @spec unavailable() :: t()
  def unavailable do
    %__MODULE__{state: :unavailable, label: "Unavailable", tone: :blocked}
  end

  @doc "Validates bounded, host-standard status data before composition."
  def valid?(%__MODULE__{
        state: state,
        label: label,
        tone: tone,
        facts: facts,
        outstanding_actions: actions
      }) do
    is_atom(state) and not is_nil(state) and tone in [:ready, :attention, :blocked, :info] and
      text?(label) and bounded_list?(facts, &fact?/1) and bounded_list?(actions, &text?/1)
  end

  def valid?(_status), do: false

  defp bounded_list?(values, check),
    do: is_list(values) and length(values) <= 64 and Enum.all?(values, check)

  defp fact?(%{id: id, label: label, value: value}),
    do: text?(id) and text?(label) and text?(value)

  defp fact?(_fact), do: false
  defp text?(value), do: is_binary(value) and byte_size(value) <= 4096 and String.valid?(value)
end
