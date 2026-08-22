defmodule CCSDS.CFDP.Transition do
  @moduledoc """
  Result of one pure CFDP state-machine transition.

  Timer effects use caller-owned clocks. A `{:start, name}` effect starts or
  restarts the applicable managed timer and `{:cancel, name}` cancels it.
  File effects are ordered and must be applied in list order.
  """

  alias CCSDS.CFDP.{FileEffect, Indication, PDU}

  @type timer :: :check | :nak | :positive_ack | :inactivity
  @type timer_effect :: {:start | :cancel, timer()}

  @type t(state) :: %__MODULE__{
          state: state,
          pdus: [PDU.t()],
          indications: [Indication.t()],
          timers: [timer_effect()],
          effects: [FileEffect.t()]
        }

  @enforce_keys [:state]
  defstruct [:state, pdus: [], indications: [], timers: [], effects: []]

  @spec new(state, keyword()) :: t(state) when state: term()
  def new(state, opts \\ []) do
    %__MODULE__{
      state: state,
      pdus: Keyword.get(opts, :pdus, []),
      indications: Keyword.get(opts, :indications, []),
      timers: Keyword.get(opts, :timers, []),
      effects: Keyword.get(opts, :effects, [])
    }
  end
end
