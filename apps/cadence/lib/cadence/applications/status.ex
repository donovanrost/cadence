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
end
