defmodule Cadence.CCSDS.Test.COP1FOPFixtures do
  @moduledoc false

  alias Cadence.CCSDS.Transport.COP1.{CLCW, FOP}

  def state(attrs \\ %{}) do
    defaults = %{
      enabled: true,
      vcid: 0,
      state: :active,
      lower_layer_mode: :explicit,
      sliding_window_width: 4,
      t1_initial_ms: 100,
      transmission_limit: 3
    }

    FOP.new(Map.merge(defaults, Map.new(attrs)))
  end

  def sent_state(state_name, sequences, attrs \\ %{}) when is_list(sequences) do
    attrs = Map.new(attrs)
    nnr = Map.get(attrs, :nnr, List.first(sequences) || 0)
    vs = Map.get(attrs, :vs, Integer.mod(nnr + length(sequences), 256))

    entries =
      Enum.map(sequences, fn sequence ->
        %{
          frame_type: :ad,
          frame: %{seq: sequence, frame_base64: Base.encode64(<<sequence>>), retries: 0},
          control_command: nil,
          request: {:request, sequence},
          retransmit?: false
        }
      end)

    overrides =
      attrs
      |> Map.drop([:nnr, :vs])
      |> Map.merge(%{
        state: state_name,
        nnr: nnr,
        vs: vs,
        sent_queue: entries,
        timer_running: true
      })

    state(overrides)
  end

  def bc_state(attrs \\ %{}) do
    directive = %{type: :initiate_ad_with_unlock, qualifier: nil, request_id: :initialize}

    entry = %{
      frame_type: :bc,
      frame: nil,
      control_command: :unlock,
      request: directive,
      retransmit?: false
    }

    state(
      Map.merge(
        %{
          state: :initializing_with_bc,
          sent_queue: [entry],
          pending_directive: directive,
          timer_running: true
        },
        Map.new(attrs)
      )
    )
  end

  def clcw(attrs \\ %{}) do
    CLCW.new(Map.merge(%{vcid: 0, cop_in_effect: 1}, Map.new(attrs)))
  end
end
