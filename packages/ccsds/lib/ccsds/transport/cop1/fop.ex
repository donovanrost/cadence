defmodule CCSDS.Transport.COP1.FOP do
  @moduledoc """
  Pure COP-1 Frame Operation Procedure (FOP-1 Revision B).

  The module models one sending-side TC Virtual Channel. It implements the six
  FOP-1 states, AD/BD service requests, all standard directives, lower-layer
  AD/BC/BD responses, the single T1 timer, CLCW event classification, sliding
  window retransmission, suspend/resume, and standardized alert reasons.

  `:lower_layer_mode` controls composition with the lower procedure. The
  standard `:explicit` mode requires `lower_layer_response/2` for every
  transmit request. `:synchronous` folds successful lower-layer acceptance into
  transmission and is intended for application boundaries where accepting an
  emitted request already constitutes the LLIF accept response.
  """

  alias CCSDS.Transport.COP1.CLCW
  alias CCSDS.Transport.COP1.FOP.Transition

  @type state_name ::
          :active
          | :retransmit_without_wait
          | :retransmit_with_wait
          | :initializing_without_bc
          | :initializing_with_bc
          | :initial

  @type lower_layer_mode :: :explicit | :synchronous
  @type timeout_type :: 0 | 1
  @type suspend_state :: 0..4

  @type frame_entry :: %{
          optional(:seq) => 0..255,
          optional(:frame_base64) => binary(),
          optional(:retries) => non_neg_integer(),
          optional(atom()) => term()
        }

  @type directive_type ::
          :initiate_ad_without_clcw_check
          | :initiate_ad_with_clcw_check
          | :initiate_ad_with_unlock
          | :initiate_ad_with_set_vr
          | :terminate_ad
          | :resume_ad
          | :set_vs
          | :set_fop_sliding_window_width
          | :set_t1_initial
          | :set_transmission_limit
          | :set_timeout_type

  @type directive :: %{type: directive_type() | term(), qualifier: term(), request_id: term()}

  @type sent_entry :: %{
          frame_type: :ad | :bc,
          frame: frame_entry() | nil,
          control_command: term() | nil,
          request: term(),
          retransmit?: boolean()
        }

  @type t :: %__MODULE__{
          enabled: boolean(),
          vcid: 0..63 | nil,
          state: state_name(),
          vs: 0..255,
          nnr: 0..255,
          wait_queue: %{frame: frame_entry(), request: term()} | nil,
          sent_queue: [sent_entry()],
          ad_out_ready: boolean(),
          bc_out_ready: boolean(),
          bd_out_ready: boolean(),
          t1_initial_ms: pos_integer(),
          transmission_limit: pos_integer(),
          transmission_count: pos_integer(),
          sliding_window_width: 1..255,
          timeout_type: timeout_type(),
          suspend_state: suspend_state(),
          timer_running: boolean(),
          pending_directive: directive() | nil,
          pending_bd: term() | nil,
          lower_layer_mode: lower_layer_mode(),
          in_flight_release: map() | nil,
          lockout: boolean(),
          wait: boolean(),
          retransmit: boolean(),
          last_report_value: 0..255 | nil,
          timeout_ms: pos_integer(),
          max_retransmit: non_neg_integer()
        }

  defstruct enabled: false,
            vcid: nil,
            state: :initial,
            vs: 0,
            nnr: 0,
            wait_queue: nil,
            sent_queue: [],
            ad_out_ready: true,
            bc_out_ready: true,
            bd_out_ready: true,
            t1_initial_ms: 5_000,
            transmission_limit: 4,
            transmission_count: 1,
            sliding_window_width: 1,
            timeout_type: 0,
            suspend_state: 0,
            timer_running: false,
            pending_directive: nil,
            pending_bd: nil,
            lower_layer_mode: :explicit,
            in_flight_release: nil,
            lockout: false,
            wait: false,
            retransmit: false,
            last_report_value: nil,
            timeout_ms: 5_000,
            max_retransmit: 3

  @spec new(map() | keyword()) :: t()
  def new(attrs \\ %{}) when is_map(attrs) or is_list(attrs) do
    case init(attrs) do
      {:ok, state} -> state
      {:error, reason} -> raise ArgumentError, "invalid FOP-1 configuration: #{inspect(reason)}"
    end
  end

  @spec init(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def init(attrs \\ %{}) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)
    known_fields = Map.keys(Map.from_struct(%__MODULE__{})) ++ [:initial_vs]

    with [] <- Map.keys(attrs) -- known_fields,
         normalized = normalize_compatibility_attrs(attrs),
         state = struct(__MODULE__, normalized),
         :ok <- validate_boolean(state.enabled, :enabled),
         :ok <- validate_optional_range(state.vcid, 0, 63, :vcid),
         :ok <- validate_state_name(state.state),
         :ok <- validate_range(state.vs, 0, 255, :vs),
         :ok <- validate_range(state.nnr, 0, 255, :nnr),
         :ok <- validate_positive(state.t1_initial_ms, :t1_initial_ms),
         :ok <- validate_positive(state.transmission_limit, :transmission_limit),
         :ok <- validate_positive(state.transmission_count, :transmission_count),
         :ok <- validate_range(state.sliding_window_width, 1, 255, :sliding_window_width),
         :ok <- validate_member(state.timeout_type, [0, 1], :timeout_type),
         :ok <- validate_range(state.suspend_state, 0, 4, :suspend_state),
         :ok <-
           validate_member(state.lower_layer_mode, [:explicit, :synchronous], :lower_layer_mode),
         :ok <- validate_boolean(state.timer_running, :timer_running) do
      {:ok,
       %{
         state
         | timeout_ms: state.t1_initial_ms,
           max_retransmit: state.transmission_limit - 1
       }}
    else
      [_unknown | _rest] -> {:error, :unknown_fop_attribute}
      {:error, _reason} = error -> error
    end
  end

  @spec directive(t(), directive_type() | term(), term(), keyword()) ::
          {:ok, Transition.t()}
  def directive(%__MODULE__{} = state, type, qualifier \\ nil, opts \\ []) do
    directive = %{
      type: type,
      qualifier: qualifier,
      request_id: Keyword.get(opts, :request_id)
    }

    case validate_directive(directive) do
      :ok -> {:ok, apply_directive(state, directive)}
      {:error, _reason} -> {:ok, reject_directive(state, directive, :e40)}
    end
  end

  @spec request_ad(t(), frame_entry(), term()) :: {:ok, Transition.t()}
  def request_ad(%__MODULE__{} = state, frame, request \\ nil) when is_map(frame) do
    transition = Transition.new(state)

    cond do
      state.state not in [:active, :retransmit_without_wait, :retransmit_with_wait] ->
        {:ok,
         transition
         |> Transition.put_event(:e19)
         |> Transition.add_notification({:fdu, :reject, request})}

      not is_nil(state.wait_queue) ->
        {:ok,
         transition
         |> Transition.put_event(:e20)
         |> Transition.add_notification({:fdu, :reject, request})}

      true ->
        next_state = %{state | wait_queue: %{frame: frame, request: request}}

        {:ok,
         transition
         |> Transition.put_event(:e19)
         |> Transition.put_state(next_state)
         |> look_for_fdu()}
    end
  end

  @spec request_bd(t(), frame_entry(), term()) :: {:ok, Transition.t()}
  def request_bd(%__MODULE__{} = state, frame, request \\ nil) when is_map(frame) do
    transition = Transition.new(state)

    if state.bd_out_ready do
      next_state = %{
        state
        | bd_out_ready: synchronous?(state),
          pending_bd: if(synchronous?(state), do: nil, else: request)
      }

      transition =
        transition
        |> Transition.put_event(:e21)
        |> Transition.put_state(next_state)
        |> Transition.add_notification({:fdu, :accept, request})
        |> Transition.add_transmit(:bd, Map.put_new(frame, :retries, 0))

      transition =
        if synchronous?(state) do
          Transition.add_notification(transition, {:fdu, :positive_confirm, request})
        else
          transition
        end

      {:ok, transition}
    else
      {:ok,
       transition
       |> Transition.put_event(:e22)
       |> Transition.add_notification({:fdu, :reject, request})}
    end
  end

  @doc """
  Convenience adapter for one pre-framed command release.

  The adapter preserves caller-supplied release-level start/completion
  correlation while the FOP state itself uses the standard Sent_Queue and
  V(S)/NN(R) variables. It is only available in synchronous lower-layer mode.
  """
  @spec accept_release(t(), term(), [frame_entry()]) ::
          {:ok, Transition.t()} | {:error, term()}
  def accept_release(%__MODULE__{enabled: false}, _base_request, _frames),
    do: {:error, :cop1_disabled}

  def accept_release(%__MODULE__{state: :initial}, _base_request, _frames),
    do: {:error, :cop1_not_initialized}

  def accept_release(%__MODULE__{state: :initializing_without_bc}, _base_request, _frames),
    do: {:error, :cop1_initializing}

  def accept_release(%__MODULE__{state: :initializing_with_bc}, _base_request, _frames),
    do: {:error, :cop1_initializing}

  def accept_release(%__MODULE__{state: :retransmit_with_wait}, _base_request, _frames),
    do: {:error, :cop1_wait}

  def accept_release(%__MODULE__{in_flight_release: %{}}, _base_request, _frames),
    do: {:error, :cop1_window_full}

  def accept_release(%__MODULE__{}, _base_request, []), do: {:error, :empty_cop1_release}

  def accept_release(%__MODULE__{lower_layer_mode: :explicit}, _base_request, _frames),
    do: {:error, :explicit_lower_layer_requires_request_ad}

  def accept_release(%__MODULE__{} = state, base_request, frames) when is_list(frames) do
    with :ok <- validate_release_frames(state, frames),
         true <- length(frames) <= available_window(state) do
      metadata = release_metadata(base_request)
      normalized_frames = Enum.map(frames, &Map.put(&1, :retries, Map.get(&1, :retries, 0)))

      entries =
        Enum.map(normalized_frames, fn frame ->
          %{
            frame_type: :ad,
            frame: frame,
            control_command: nil,
            request: metadata,
            retransmit?: false
          }
        end)

      release = %{
        metadata: metadata,
        base_request: base_request,
        frames: normalized_frames
      }

      next_vs = increment_sequence(state.vs, length(frames))
      sent_queue_was_empty? = state.sent_queue == []

      next_state = %{
        state
        | sent_queue: state.sent_queue ++ entries,
          vs: next_vs,
          timer_running: true,
          transmission_count: if(sent_queue_was_empty?, do: 1, else: state.transmission_count),
          in_flight_release: release,
          ad_out_ready: true
      }

      transition =
        normalized_frames
        |> Enum.reduce(
          Transition.new(next_state, :e19)
          |> Transition.put_timer(:start)
          |> Transition.add_notification({:fdu, :accept, metadata})
          |> Transition.add_signal({:start, metadata}),
          fn frame, acc -> Transition.add_transmit(acc, :ad, frame) end
        )

      {:ok, transition}
    else
      false -> {:error, :cop1_window_full}
      {:error, _reason} = error -> error
    end
  end

  @spec apply_clcw(t(), CLCW.t()) :: {:ok, Transition.t()}
  def apply_clcw(%__MODULE__{} = state, %CLCW{} = clcw) do
    cond do
      clcw.cop_in_effect != 1 ->
        {:ok, Transition.new(state, :ignored_clcw)}

      not is_nil(state.vcid) and clcw.vcid != state.vcid ->
        {:ok, Transition.new(state, :ignored_clcw)}

      true ->
        event = classify_clcw_event(state, clcw)
        observed_state = observe_clcw(state, clcw)
        {:ok, apply_clcw_event(Transition.new(observed_state, event), clcw)}
    end
  end

  @spec timer_expired(t()) :: {:ok, Transition.t()}
  def timer_expired(%__MODULE__{} = state) do
    state = %{state | timer_running: false}
    event = classify_timer_event(state)
    {:ok, apply_timer_event(Transition.new(state, event))}
  end

  @spec handle_timeout(t(), non_neg_integer()) :: {:ok, Transition.t()}
  def handle_timeout(%__MODULE__{} = state, _sequence_number), do: timer_expired(state)

  @spec lower_layer_response(t(), atom()) :: {:ok, Transition.t()}
  def lower_layer_response(%__MODULE__{} = state, response)
      when response in [:ad_accept, :ad_reject, :bc_accept, :bc_reject, :bd_accept, :bd_reject] do
    {:ok, apply_lower_layer_response(Transition.new(state), response)}
  end

  defp apply_directive(state, %{type: :initiate_ad_without_clcw_check} = directive) do
    if state.state == :initial do
      Transition.new(state, :e23)
      |> Transition.add_notification({:directive, :accept, directive})
      |> initialize()
      |> set_state(:active)
      |> Transition.add_notification({:directive, :positive_confirm, directive})
    else
      reject_directive(state, directive, :e23)
    end
  end

  defp apply_directive(state, %{type: :initiate_ad_with_clcw_check} = directive) do
    if state.state == :initial do
      Transition.new(state, :e24)
      |> Transition.add_notification({:directive, :accept, directive})
      |> initialize()
      |> set_pending_directive(directive)
      |> set_state(:initializing_without_bc)
      |> start_timer()
    else
      reject_directive(state, directive, :e24)
    end
  end

  defp apply_directive(state, %{type: :initiate_ad_with_unlock} = directive) do
    cond do
      state.state != :initial -> reject_directive(state, directive, :e25)
      not state.bc_out_ready -> reject_directive(state, directive, :e26)
      true -> initialize_with_bc(state, directive, :unlock, :e25)
    end
  end

  defp apply_directive(
         state,
         %{type: :initiate_ad_with_set_vr, qualifier: receiver_frame_sequence_number} = directive
       ) do
    cond do
      state.state != :initial ->
        reject_directive(state, directive, :e27)

      not state.bc_out_ready ->
        reject_directive(state, directive, :e28)

      true ->
        state = %{
          state
          | vs: receiver_frame_sequence_number,
            nnr: receiver_frame_sequence_number
        }

        initialize_with_bc(
          state,
          directive,
          {:set_vr, receiver_frame_sequence_number},
          :e27
        )
    end
  end

  defp apply_directive(state, %{type: :terminate_ad} = directive) do
    if state.state == :initial do
      Transition.new(state, :e29)
      |> Transition.add_notification({:directive, :accept, directive})
      |> Transition.add_notification({:directive, :positive_confirm, directive})
    else
      Transition.new(state, :e29)
      |> Transition.add_notification({:directive, :accept, directive})
      |> alert(:term)
      |> Transition.add_notification({:directive, :positive_confirm, directive})
    end
  end

  defp apply_directive(state, %{type: :resume_ad} = directive) do
    case {state.state, state.suspend_state} do
      {:initial, suspend_state} when suspend_state in 1..4 ->
        resumed_state = suspend_state_name(suspend_state)

        Transition.new(state, resume_event(suspend_state))
        |> Transition.add_notification({:directive, :accept, directive})
        |> set_state(resumed_state)
        |> clear_suspend_state()
        |> start_timer()
        |> Transition.add_notification({:directive, :positive_confirm, directive})

      _other ->
        reject_directive(state, directive, :e30)
    end
  end

  defp apply_directive(state, %{type: :set_vs, qualifier: sequence_number} = directive) do
    if state.state == :initial and state.suspend_state == 0 do
      next_state = %{state | vs: sequence_number, nnr: sequence_number}

      Transition.new(next_state, :e35)
      |> Transition.add_notification({:directive, :accept, directive})
      |> Transition.add_notification({:directive, :positive_confirm, directive})
    else
      reject_directive(state, directive, :e35)
    end
  end

  defp apply_directive(
         state,
         %{type: :set_fop_sliding_window_width, qualifier: width} = directive
       ) do
    setup_directive(state, directive, :e36, %{sliding_window_width: width})
  end

  defp apply_directive(state, %{type: :set_t1_initial, qualifier: milliseconds} = directive) do
    setup_directive(state, directive, :e37, %{
      t1_initial_ms: milliseconds,
      timeout_ms: milliseconds
    })
  end

  defp apply_directive(state, %{type: :set_transmission_limit, qualifier: limit} = directive) do
    setup_directive(state, directive, :e38, %{
      transmission_limit: limit,
      max_retransmit: limit - 1
    })
  end

  defp apply_directive(state, %{type: :set_timeout_type, qualifier: timeout_type} = directive) do
    setup_directive(state, directive, :e39, %{timeout_type: timeout_type})
  end

  defp setup_directive(state, directive, event, updates) do
    next_state = struct(state, updates)

    Transition.new(next_state, event)
    |> Transition.add_notification({:directive, :accept, directive})
    |> Transition.add_notification({:directive, :positive_confirm, directive})
  end

  defp reject_directive(state, directive, event) do
    Transition.new(state, event)
    |> Transition.add_notification({:directive, :reject, directive})
  end

  defp initialize_with_bc(state, directive, control_command, event) do
    Transition.new(state, event)
    |> Transition.add_notification({:directive, :accept, directive})
    |> initialize()
    |> set_pending_directive(directive)
    |> put_bc_sent_entry(control_command)
    |> set_state(:initializing_with_bc)
    |> transmit_bc(control_command)
  end

  defp classify_clcw_event(state, clcw) do
    cond do
      invalid_clcw_pattern?(clcw) ->
        :e15

      clcw.lockout == 1 ->
        :e14

      invalid_report_value?(state, clcw.report_value) ->
        :e13

      clcw.retransmit == 0 and clcw.wait == 1 ->
        if clcw.report_value == state.vs, do: :e3, else: :e7

      clcw.report_value == state.vs ->
        classify_all_acknowledged_event(state, clcw)

      true ->
        classify_outstanding_event(state, clcw)
    end
  end

  defp classify_all_acknowledged_event(_state, %{retransmit: 1}), do: :e4

  defp classify_all_acknowledged_event(state, %{retransmit: 0, wait: 0} = clcw) do
    if clcw.report_value == state.nnr, do: :e1, else: :e2
  end

  defp classify_outstanding_event(state, %{retransmit: 0, wait: 0} = clcw) do
    if clcw.report_value == state.nnr, do: :e5, else: :e6
  end

  defp classify_outstanding_event(%{transmission_limit: 1} = state, %{retransmit: 1} = clcw) do
    if clcw.report_value == state.nnr, do: :e102, else: :e101
  end

  defp classify_outstanding_event(state, %{retransmit: 1, wait: 0} = clcw)
       when state.transmission_count < state.transmission_limit do
    if clcw.report_value == state.nnr, do: :e10, else: :e8
  end

  defp classify_outstanding_event(state, %{retransmit: 1, wait: 1} = clcw)
       when state.transmission_count < state.transmission_limit do
    if clcw.report_value == state.nnr, do: :e11, else: :e9
  end

  defp classify_outstanding_event(_state, %{retransmit: 1, wait: 0}), do: :e12
  defp classify_outstanding_event(_state, %{retransmit: 1, wait: 1}), do: :e103

  defp apply_clcw_event(%{event: :e1} = transition, _clcw), do: apply_e1(transition)

  defp apply_clcw_event(%{event: :e2} = transition, clcw),
    do: acknowledge_and_activate(transition, clcw.report_value, true)

  defp apply_clcw_event(%{event: event} = transition, _clcw) when event in [:e3, :e7],
    do: alert_unless_initial(transition, :clcw)

  defp apply_clcw_event(%{event: :e4} = transition, _clcw),
    do: alert_in_operating_states(transition, :synch)

  defp apply_clcw_event(%{event: :e5} = transition, _clcw), do: apply_e5(transition)

  defp apply_clcw_event(%{event: :e6} = transition, clcw),
    do: acknowledge_and_activate(transition, clcw.report_value, false)

  defp apply_clcw_event(%{event: :e101} = transition, clcw) do
    transition |> acknowledge(clcw.report_value) |> alert_unless_initial(:limit)
  end

  defp apply_clcw_event(%{event: :e102} = transition, _clcw),
    do: alert_unless_initial(transition, :limit)

  defp apply_clcw_event(%{event: :e8} = transition, clcw) do
    transition
    |> acknowledge(clcw.report_value)
    |> initiate_retransmission(:ad)
    |> set_state(:retransmit_without_wait)
  end

  defp apply_clcw_event(%{event: :e9} = transition, clcw) do
    transition |> acknowledge(clcw.report_value) |> set_state(:retransmit_with_wait)
  end

  defp apply_clcw_event(%{event: :e10} = transition, _clcw), do: apply_e10(transition)

  defp apply_clcw_event(%{event: :e11} = transition, _clcw),
    do: set_state(transition, :retransmit_with_wait)

  defp apply_clcw_event(%{event: :e12} = transition, _clcw),
    do: set_state(transition, :retransmit_without_wait)

  defp apply_clcw_event(%{event: :e103} = transition, _clcw),
    do: set_state(transition, :retransmit_with_wait)

  defp apply_clcw_event(%{event: :e13} = transition, _clcw),
    do: alert_in_operating_states(transition, :nnr)

  defp apply_clcw_event(%{event: :e14} = transition, _clcw),
    do: alert_in_operating_states(transition, :lockout)

  defp apply_clcw_event(%{event: :e15} = transition, _clcw),
    do: alert_unless_initial(transition, :clcw)

  defp apply_e1(%{state: %{state: :active}} = transition), do: transition

  defp apply_e1(%{state: %{state: state}} = transition)
       when state in [:retransmit_without_wait, :retransmit_with_wait],
       do: alert(transition, :synch)

  defp apply_e1(%{state: %{state: :initializing_without_bc}} = transition) do
    transition
    |> confirm_pending_directive()
    |> set_state(:active)
    |> cancel_timer()
  end

  defp apply_e1(%{state: %{state: :initializing_with_bc}} = transition) do
    transition
    |> clear_sent_queue()
    |> confirm_pending_directive()
    |> set_state(:active)
    |> cancel_timer()
  end

  defp apply_e1(transition), do: transition

  defp apply_e5(%{state: %{state: :active}} = transition), do: transition

  defp apply_e5(%{state: %{state: state}} = transition)
       when state in [:retransmit_without_wait, :retransmit_with_wait],
       do: alert(transition, :synch)

  defp apply_e5(transition), do: transition

  defp apply_e10(%{state: %{state: :retransmit_without_wait}} = transition), do: transition

  defp apply_e10(%{state: %{state: state}} = transition)
       when state in [:active, :retransmit_with_wait] do
    transition
    |> initiate_retransmission(:ad)
    |> set_state(:retransmit_without_wait)
  end

  defp apply_e10(transition), do: transition

  defp acknowledge_and_activate(transition, report_value, cancel_timer?) do
    transition =
      transition
      |> acknowledge(report_value)
      |> set_state(:active)

    transition = if cancel_timer?, do: cancel_timer(transition), else: transition
    look_for_fdu(transition)
  end

  defp classify_timer_event(state) do
    cond do
      state.transmission_count < state.transmission_limit and state.timeout_type == 0 -> :e16
      state.transmission_count < state.transmission_limit and state.timeout_type == 1 -> :e104
      state.timeout_type == 0 -> :e17
      true -> :e18
    end
  end

  defp apply_timer_event(%{state: %{state: :initial}} = transition), do: transition

  defp apply_timer_event(%{event: event, state: %{state: :initializing_with_bc}} = transition)
       when event in [:e16, :e104] do
    initiate_retransmission(transition, :bc)
  end

  defp apply_timer_event(%{event: :e16, state: %{state: :initializing_without_bc}} = transition),
    do: alert(transition, :t1)

  defp apply_timer_event(%{event: :e104, state: %{state: :initializing_without_bc}} = transition),
    do: suspend(transition, 4)

  defp apply_timer_event(%{event: event, state: %{state: state}} = transition)
       when event in [:e16, :e104] and state in [:active, :retransmit_without_wait] do
    initiate_retransmission(transition, :ad)
  end

  defp apply_timer_event(%{event: event, state: %{state: :retransmit_with_wait}} = transition)
       when event in [:e16, :e104],
       do: transition

  defp apply_timer_event(%{event: :e17} = transition), do: alert(transition, :t1)

  defp apply_timer_event(%{event: :e18, state: %{state: :initializing_with_bc}} = transition),
    do: alert(transition, :t1)

  defp apply_timer_event(%{event: :e18, state: %{state: state}} = transition) do
    suspend(transition, state_suspend_number(state))
  end

  defp apply_lower_layer_response(transition, :ad_accept) do
    next_state = %{transition.state | ad_out_ready: true}
    transition = transition |> Transition.put_event(:e41) |> Transition.put_state(next_state)

    if next_state.state in [:active, :retransmit_without_wait] do
      look_for_fdu(transition)
    else
      transition
    end
  end

  defp apply_lower_layer_response(transition, :ad_reject),
    do: transition |> Transition.put_event(:e42) |> alert(:llif)

  defp apply_lower_layer_response(transition, :bc_accept) do
    next_state = %{transition.state | bc_out_ready: true}
    transition = transition |> Transition.put_event(:e43) |> Transition.put_state(next_state)

    if next_state.state == :initializing_with_bc do
      look_for_directive(transition)
    else
      transition
    end
  end

  defp apply_lower_layer_response(transition, :bc_reject),
    do: transition |> Transition.put_event(:e44) |> alert(:llif)

  defp apply_lower_layer_response(transition, :bd_accept) do
    request = transition.state.pending_bd
    next_state = %{transition.state | bd_out_ready: true, pending_bd: nil}

    transition
    |> Transition.put_event(:e45)
    |> Transition.put_state(next_state)
    |> Transition.add_notification({:fdu, :positive_confirm, request})
  end

  defp apply_lower_layer_response(transition, :bd_reject),
    do: transition |> Transition.put_event(:e46) |> alert(:llif)

  defp look_for_fdu(%{state: %{state: :retransmit_with_wait}} = transition), do: transition
  defp look_for_fdu(%{state: %{ad_out_ready: false}} = transition), do: transition

  defp look_for_fdu(transition) do
    case Enum.find_index(transition.state.sent_queue, & &1.retransmit?) do
      nil -> maybe_transmit_waiting_fdu(transition)
      index -> transmit_requeued_ad(transition, index)
    end
  end

  defp transmit_requeued_ad(transition, index) do
    entry = Enum.at(transition.state.sent_queue, index)
    next_entry = %{entry | retransmit?: false}
    sent_queue = List.replace_at(transition.state.sent_queue, index, next_entry)

    next_state = %{
      transition.state
      | sent_queue: sent_queue,
        ad_out_ready: synchronous?(transition.state)
    }

    transition =
      transition
      |> Transition.put_state(next_state)
      |> Transition.add_transmit(:ad, next_entry.frame)

    if synchronous?(next_state), do: look_for_fdu(transition), else: transition
  end

  defp maybe_transmit_waiting_fdu(%{state: %{wait_queue: nil}} = transition), do: transition

  defp maybe_transmit_waiting_fdu(transition) do
    if available_window(transition.state) > 0 do
      %{frame: frame, request: request} = transition.state.wait_queue
      frame = frame |> Map.put(:seq, transition.state.vs) |> Map.put_new(:retries, 0)

      entry = %{
        frame_type: :ad,
        frame: frame,
        control_command: nil,
        request: request,
        retransmit?: false
      }

      sent_queue_was_empty? = transition.state.sent_queue == []

      next_state = %{
        transition.state
        | wait_queue: nil,
          sent_queue: transition.state.sent_queue ++ [entry],
          vs: increment_sequence(transition.state.vs, 1),
          transmission_count:
            if(sent_queue_was_empty?, do: 1, else: transition.state.transmission_count),
          timer_running: true,
          ad_out_ready: synchronous?(transition.state)
      }

      transition =
        transition
        |> Transition.put_state(next_state)
        |> Transition.put_timer(:start)
        |> Transition.add_notification({:fdu, :accept, request})
        |> Transition.add_transmit(:ad, frame)

      if synchronous?(next_state), do: look_for_fdu(transition), else: transition
    else
      transition
    end
  end

  defp initiate_retransmission(transition, frame_type) do
    sent_queue =
      Enum.map(transition.state.sent_queue, &mark_for_retransmission(&1, frame_type))

    next_state = %{
      transition.state
      | sent_queue: sent_queue,
        transmission_count: transition.state.transmission_count + 1,
        timer_running: true,
        in_flight_release: update_release_retries(transition.state.in_flight_release, sent_queue)
    }

    transition =
      transition
      |> Transition.put_state(next_state)
      |> Transition.abort_lower()
      |> Transition.put_timer(:start)

    case frame_type do
      :ad -> look_for_fdu(transition)
      :bc -> look_for_directive(transition)
    end
  end

  defp look_for_directive(%{state: %{bc_out_ready: false}} = transition), do: transition

  defp look_for_directive(transition) do
    case Enum.find_index(
           transition.state.sent_queue,
           &(&1.frame_type == :bc and &1.retransmit?)
         ) do
      nil ->
        transition

      index ->
        entry = Enum.at(transition.state.sent_queue, index)

        sent_queue =
          List.replace_at(transition.state.sent_queue, index, %{entry | retransmit?: false})

        next_state = %{
          transition.state
          | sent_queue: sent_queue,
            bc_out_ready: synchronous?(transition.state)
        }

        transition
        |> Transition.put_state(next_state)
        |> Transition.add_transmit(:bc, nil, entry.control_command)
    end
  end

  defp acknowledge(transition, report_value) do
    count = sequence_distance(transition.state.nnr, report_value)
    {acknowledged, remaining} = Enum.split(transition.state.sent_queue, count)

    acknowledged_sequences =
      acknowledged |> Enum.map(& &1.frame) |> Enum.reject(&is_nil/1) |> Enum.map(& &1.seq)

    transition =
      Enum.reduce(acknowledged, transition, fn entry, acc ->
        Transition.add_notification(acc, {:fdu, :positive_confirm, entry.request})
      end)

    next_release = update_release_after_ack(transition.state.in_flight_release, remaining)

    transition =
      transition
      |> Transition.cancel_sequences(acknowledged_sequences)
      |> Transition.put_state(%{
        transition.state
        | sent_queue: remaining,
          nnr: report_value,
          transmission_count: 1,
          in_flight_release: next_release
      })

    maybe_complete_release(transition)
  end

  defp maybe_complete_release(%{state: %{in_flight_release: nil}} = transition), do: transition

  defp maybe_complete_release(transition) do
    case transition.state.in_flight_release do
      %{frames: []} = release ->
        next_state = %{transition.state | in_flight_release: nil}

        transition
        |> Transition.put_state(next_state)
        |> Transition.add_signal({:completion, release.metadata})

      _other ->
        transition
    end
  end

  defp alert_unless_initial(%{state: %{state: :initial}} = transition, _reason), do: transition
  defp alert_unless_initial(transition, reason), do: alert(transition, reason)

  defp alert_in_states(transition, reason, states) do
    if transition.state.state in states, do: alert(transition, reason), else: transition
  end

  defp alert_in_operating_states(transition, reason) do
    alert_in_states(transition, reason, [
      :active,
      :retransmit_without_wait,
      :retransmit_with_wait,
      :initializing_without_bc
    ])
  end

  defp alert(transition, reason) do
    transition = purge_queues(transition, reason)
    pending_directive = transition.state.pending_directive

    next_state = %{
      transition.state
      | state: :initial,
        sent_queue: [],
        wait_queue: nil,
        timer_running: false,
        transmission_count: 1,
        pending_directive: nil,
        pending_bd: nil,
        in_flight_release: nil
    }

    transition =
      transition
      |> Transition.put_state(next_state)
      |> Transition.put_timer(:cancel)
      |> Transition.add_alert(reason)

    if pending_directive do
      Transition.add_notification(
        transition,
        {:directive, :negative_confirm, pending_directive}
      )
    else
      transition
    end
  end

  defp suspend(transition, suspend_state) when suspend_state in 1..4 do
    next_state = %{
      transition.state
      | state: :initial,
        suspend_state: suspend_state,
        timer_running: false
    }

    transition
    |> Transition.put_state(next_state)
    |> Transition.add_notification({:suspend, suspend_state})
  end

  defp initialize(transition) do
    transition = purge_queues(transition, :initialize)

    next_state = %{
      transition.state
      | wait_queue: nil,
        sent_queue: [],
        transmission_count: 1,
        suspend_state: 0,
        timer_running: false,
        pending_directive: nil,
        in_flight_release: nil
    }

    Transition.put_state(transition, next_state)
  end

  defp purge_queues(transition, reason) do
    sent_requests =
      transition.state.sent_queue
      |> Enum.filter(&(&1.frame_type == :ad))
      |> Enum.map(& &1.request)
      |> Enum.uniq()

    sequences =
      transition.state.sent_queue
      |> Enum.map(& &1.frame)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(& &1.seq)

    transition =
      Enum.reduce(sent_requests, transition, fn request, acc ->
        Transition.add_notification(acc, {:fdu, :negative_confirm, request})
      end)

    transition =
      case transition.state.wait_queue do
        %{request: request} -> Transition.add_notification(transition, {:fdu, :reject, request})
        nil -> transition
      end

    transition = Transition.cancel_sequences(transition, sequences)

    case transition.state.in_flight_release do
      %{metadata: metadata} -> Transition.add_signal(transition, {:failure, metadata, reason})
      _other -> transition
    end
  end

  defp confirm_pending_directive(transition) do
    case transition.state.pending_directive do
      nil ->
        transition

      directive ->
        next_state = %{transition.state | pending_directive: nil}

        transition
        |> Transition.put_state(next_state)
        |> Transition.add_notification({:directive, :positive_confirm, directive})
    end
  end

  defp clear_sent_queue(transition) do
    next_state = %{transition.state | sent_queue: [], transmission_count: 1}
    Transition.put_state(transition, next_state)
  end

  defp set_pending_directive(transition, directive) do
    Transition.put_state(transition, %{transition.state | pending_directive: directive})
  end

  defp put_bc_sent_entry(transition, control_command) do
    entry = %{
      frame_type: :bc,
      frame: nil,
      control_command: control_command,
      request: transition.state.pending_directive,
      retransmit?: false
    }

    next_state = %{
      transition.state
      | sent_queue: [entry],
        transmission_count: 1,
        timer_running: true
    }

    Transition.put_state(transition, next_state)
  end

  defp transmit_bc(transition, control_command) do
    next_state = %{
      transition.state
      | bc_out_ready: synchronous?(transition.state),
        timer_running: true
    }

    transition
    |> Transition.put_state(next_state)
    |> Transition.put_timer(:start)
    |> Transition.add_transmit(:bc, nil, control_command)
  end

  defp set_state(transition, state_name) do
    Transition.put_state(transition, %{transition.state | state: state_name})
  end

  defp clear_suspend_state(transition) do
    Transition.put_state(transition, %{transition.state | suspend_state: 0})
  end

  defp start_timer(transition) do
    transition
    |> Transition.put_state(%{transition.state | timer_running: true})
    |> Transition.put_timer(:start)
  end

  defp cancel_timer(transition) do
    transition
    |> Transition.put_state(%{transition.state | timer_running: false})
    |> Transition.put_timer(:cancel)
  end

  defp observe_clcw(state, clcw) do
    %{
      state
      | lockout: clcw.lockout == 1,
        wait: clcw.wait == 1,
        retransmit: clcw.retransmit == 1,
        last_report_value: clcw.report_value
    }
  end

  defp invalid_clcw_pattern?(clcw) do
    clcw.control_word_type != 0 or clcw.version != 0 or clcw.spare_1 != 0 or
      clcw.spare_2 != 0
  end

  defp invalid_report_value?(state, report_value) do
    sequence_distance(state.nnr, report_value) > sequence_distance(state.nnr, state.vs)
  end

  defp available_window(state) do
    state.sliding_window_width - sequence_distance(state.nnr, state.vs)
  end

  defp validate_release_frames(state, frames) do
    expected_sequences =
      state.vs
      |> Stream.iterate(&increment_sequence(&1, 1))
      |> Enum.take(length(frames))

    actual_sequences = Enum.map(frames, &Map.get(&1, :seq))

    if actual_sequences == expected_sequences do
      :ok
    else
      {:error, {:unexpected_frame_sequences, expected_sequences, actual_sequences}}
    end
  end

  defp update_release_retries(nil, _sent_queue), do: nil

  defp update_release_retries(release, sent_queue) do
    frames = sent_queue |> Enum.filter(&(&1.frame_type == :ad)) |> Enum.map(& &1.frame)
    %{release | frames: frames}
  end

  defp update_release_after_ack(nil, _remaining), do: nil

  defp update_release_after_ack(release, remaining) do
    frames = remaining |> Enum.filter(&(&1.frame_type == :ad)) |> Enum.map(& &1.frame)
    %{release | frames: frames}
  end

  defp release_metadata(base_request) do
    %{
      command_release_attempt_id: Map.fetch!(base_request, :command_release_attempt_id),
      command_request_id: Map.fetch!(base_request, :command_request_id),
      command_name: Map.get(base_request, :command_name),
      source_endpoint_ref: Map.get(base_request, :source_endpoint_ref)
    }
  end

  defp validate_directive(%{type: type, qualifier: nil})
       when type in [
              :initiate_ad_without_clcw_check,
              :initiate_ad_with_clcw_check,
              :initiate_ad_with_unlock,
              :terminate_ad,
              :resume_ad
            ],
       do: :ok

  defp validate_directive(%{type: :initiate_ad_with_set_vr, qualifier: value}),
    do: validate_range(value, 0, 255, :receiver_frame_sequence_number)

  defp validate_directive(%{type: :set_vs, qualifier: value}),
    do: validate_range(value, 0, 255, :vs)

  defp validate_directive(%{type: :set_fop_sliding_window_width, qualifier: value}),
    do: validate_range(value, 1, 255, :sliding_window_width)

  defp validate_directive(%{type: :set_t1_initial, qualifier: value}),
    do: validate_positive(value, :t1_initial_ms)

  defp validate_directive(%{type: :set_transmission_limit, qualifier: value}),
    do: validate_positive(value, :transmission_limit)

  defp validate_directive(%{type: :set_timeout_type, qualifier: value}),
    do: validate_member(value, [0, 1], :timeout_type)

  defp validate_directive(_directive), do: {:error, :invalid_directive}

  defp normalize_compatibility_attrs(attrs) do
    t1_initial_ms = Map.get(attrs, :t1_initial_ms, Map.get(attrs, :timeout_ms, 5_000))

    transmission_limit =
      case Map.fetch(attrs, :transmission_limit) do
        {:ok, value} -> value
        :error -> increment_compatibility_limit(Map.get(attrs, :max_retransmit, 3))
      end

    vs = Map.get(attrs, :vs, Map.get(attrs, :initial_vs, 0))
    nnr = Map.get(attrs, :nnr, vs)

    attrs
    |> Map.put(:t1_initial_ms, t1_initial_ms)
    |> Map.put(:timeout_ms, t1_initial_ms)
    |> Map.put(:transmission_limit, transmission_limit)
    |> Map.put(:max_retransmit, decrement_compatibility_limit(transmission_limit))
    |> Map.put(:vs, vs)
    |> Map.put(:nnr, nnr)
  end

  defp synchronous?(state), do: state.lower_layer_mode == :synchronous

  defp mark_for_retransmission(%{frame_type: frame_type} = entry, frame_type) do
    %{entry | retransmit?: true, frame: increment_frame_retry(entry.frame)}
  end

  defp mark_for_retransmission(entry, _frame_type), do: entry

  defp increment_frame_retry(nil), do: nil
  defp increment_frame_retry(frame), do: Map.update(frame, :retries, 1, &(&1 + 1))

  defp increment_compatibility_limit(value) when is_integer(value), do: value + 1
  defp increment_compatibility_limit(value), do: value
  defp decrement_compatibility_limit(value) when is_integer(value), do: value - 1
  defp decrement_compatibility_limit(value), do: value

  defp sequence_distance(base, sequence), do: Integer.mod(sequence - base, 256)
  defp increment_sequence(sequence, count), do: Integer.mod(sequence + count, 256)

  defp suspend_state_name(1), do: :active
  defp suspend_state_name(2), do: :retransmit_without_wait
  defp suspend_state_name(3), do: :retransmit_with_wait
  defp suspend_state_name(4), do: :initializing_without_bc

  defp resume_event(1), do: :e31
  defp resume_event(2), do: :e32
  defp resume_event(3), do: :e33
  defp resume_event(4), do: :e34

  defp state_suspend_number(:active), do: 1
  defp state_suspend_number(:retransmit_without_wait), do: 2
  defp state_suspend_number(:retransmit_with_wait), do: 3
  defp state_suspend_number(:initializing_without_bc), do: 4

  defp validate_state_name(state)
       when state in [
              :active,
              :retransmit_without_wait,
              :retransmit_with_wait,
              :initializing_without_bc,
              :initializing_with_bc,
              :initial
            ],
       do: :ok

  defp validate_state_name(state), do: {:error, {:invalid_field, :state, state}}

  defp validate_boolean(value, _field) when is_boolean(value), do: :ok
  defp validate_boolean(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_optional_range(nil, _min, _max, _field), do: :ok
  defp validate_optional_range(value, min, max, field), do: validate_range(value, min, max, field)

  defp validate_range(value, min, max, _field)
       when is_integer(value) and value >= min and value <= max,
       do: :ok

  defp validate_range(value, _min, _max, field),
    do: {:error, {:invalid_field, field, value}}

  defp validate_positive(value, _field) when is_integer(value) and value > 0, do: :ok
  defp validate_positive(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_member(value, allowed, field) do
    if value in allowed, do: :ok, else: {:error, {:invalid_field, field, value}}
  end
end
