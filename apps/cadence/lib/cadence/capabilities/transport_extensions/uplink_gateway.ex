# credo:disable-for-this-file Credo.Check.Refactor.Nesting
defmodule Cadence.Capabilities.TransportExtensions.UplinkGateway do
  @moduledoc """
  Transport extension that frames command payloads into CCSDS TC transfer frames.

  It supports two runtime modes:
  - direct framed uplink with optional simulated later phases
  - a narrow COP-1 FOP mode driven by CLCW reports and timeout retransmit
  """

  @behaviour Cadence.Capabilities.Family
  @behaviour Cadence.Capabilities.TransportExtension

  alias Cadence.ActionRequests.{CancelTimer, ProviderRequest, ScheduleTimer, UplinkRequest}
  alias Cadence.CCSDS.Core.SDUOctets
  alias Cadence.CCSDS.TC.{FrameCodec, Segmentation}
  alias Cadence.CCSDS.Transport.COP1.{CLCW, FOP}

  alias Cadence.Capabilities.{
    Descriptor,
    ExecutionContext,
    ExecutionResult,
    ValidationContext
  }

  @default_transport_profile :tc
  @default_frame_size 32
  @default_cop1_timeout_ms 5_000
  @default_cop1_max_retransmit 3
  @cop1_timeout_timer_prefix "cop1:timeout:"
  @start_timer_prefix "uplink:start:"
  @completion_timer_prefix "uplink:completion:"

  @impl true
  def descriptor do
    Descriptor.new(%{
      family_key: :uplink_gateway,
      kind: :transport_extension,
      supported_scopes: [:path, :transport],
      input_stages: [],
      partition_affinity: :path,
      config_schema: nil,
      emitted_record_kinds: [],
      emitted_action_kinds: [:uplink_request, :provider_request, :schedule_timer, :cancel_timer],
      replay_mode: :deterministic,
      state_mode: :stateful
    })
  end

  @impl true
  def validate_config(configuration, %ValidationContext{}) do
    with {:ok, normalized_configuration} <- normalize_configuration(configuration) do
      validate_configuration(normalized_configuration)
    end
  end

  @impl true
  def build_instance(configuration, _activation_context) do
    with {:ok, normalized_configuration} <- normalize_configuration(configuration),
         :ok <- validate_configuration(normalized_configuration) do
      {:ok, normalized_configuration}
    end
  end

  @impl true
  def init_transport(configuration, %ExecutionContext{}) do
    with {:ok, normalized_configuration} <- normalize_configuration(configuration),
         :ok <- validate_configuration(normalized_configuration) do
      {:ok,
       ExecutionResult.new(%{
         state: %{
           service_name: normalized_configuration.service_name,
           transport_profile: normalized_configuration.transport_profile,
           frame_size: normalized_configuration.frame_size,
           scid: normalized_configuration.scid,
           vcid: normalized_configuration.vcid,
           bypass_flag: normalized_configuration.bypass_flag,
           control_command_flag: normalized_configuration.control_command_flag,
           segment_header_flag: normalized_configuration.segment_header_flag,
           next_frame_seq: normalized_configuration.initial_frame_seq,
           cop1_mode: normalized_configuration.cop1_mode,
           cop1_timeout_ms: normalized_configuration.cop1_timeout_ms,
           cop1_max_retransmit: normalized_configuration.cop1_max_retransmit,
           cop1:
             build_cop1_state(
               normalized_configuration.cop1_mode,
               normalized_configuration.vcid,
               normalized_configuration.cop1_timeout_ms,
               normalized_configuration.cop1_max_retransmit
             ),
           simulated_start_delay_ms: normalized_configuration.simulated_start_delay_ms,
           simulated_completion_delay_ms: normalized_configuration.simulated_completion_delay_ms,
           provider_binding_id: normalized_configuration.provider_binding_id,
           provider_adapter_key: normalized_configuration.provider_adapter_key,
           accepted_uplink_count: 0,
           started_uplink_count: 0,
           completed_uplink_count: 0,
           last_release_attempt_id: nil,
           last_command_request_id: nil,
           last_command_name: nil,
           last_signal_phase: nil,
           last_signal_at: nil,
           last_control_at: nil,
           active_releases: %{}
         }
       })}
    end
  end

  @impl true
  def handle_transport_event(event, app_state, %ExecutionContext{} = ctx)
      when is_map(app_state) do
    with {:ok, %CLCW{} = clcw} <- normalize_cop1_clcw_event(event),
         true <- cop1_enabled?(app_state),
         {:ok, transition} <- FOP.apply_clcw(app_state.cop1, clcw) do
      {:ok, build_cop1_execution_result(app_state, transition, ctx.current_time)}
    else
      false ->
        {:ok, ExecutionResult.new(%{state: app_state})}

      {:error, :not_cop1_clcw_event} ->
        {:ok, ExecutionResult.new(%{state: app_state})}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def handle_transport_event(_event, app_state, %ExecutionContext{}) do
    {:error, {:invalid_uplink_gateway_state, app_state}}
  end

  @impl true
  def handle_control_input(
        %UplinkRequest{} = uplink_request,
        app_state,
        %ExecutionContext{} = ctx
      )
      when is_map(app_state) do
    case accepts_service?(app_state.service_name, uplink_request.preferred_uplink_service) do
      true ->
        with {:ok, framed_uplink_request, next_frame_seq} <-
               frame_uplink_request(uplink_request, app_state, ctx.current_time) do
          case cop1_strategy(app_state, framed_uplink_request) do
            :fop ->
              handle_cop1_release(framed_uplink_request, app_state, next_frame_seq, ctx)

            :direct ->
              {:ok,
               build_direct_execution_result(
                 framed_uplink_request,
                 app_state,
                 next_frame_seq,
                 ctx.current_time
               )}
          end
        end

      false ->
        {:error,
         {:uplink_gateway_service_mismatch, app_state.service_name,
          uplink_request.preferred_uplink_service}}
    end
  end

  def handle_control_input(control_input, app_state, %ExecutionContext{})
      when is_map(app_state) do
    {:error, {:unsupported_uplink_gateway_control_input, control_input}}
  end

  def handle_control_input(_control_input, app_state, %ExecutionContext{}) do
    {:error, {:invalid_uplink_gateway_state, app_state}}
  end

  @impl true
  def handle_timer(timer_key, app_state, %ExecutionContext{} = ctx) when is_map(app_state) do
    case parse_timer_key(timer_key) do
      {:cop1_timeout, command_release_attempt_id, seq} ->
        handle_cop1_timeout(command_release_attempt_id, seq, app_state, ctx)

      {:start, command_release_attempt_id} ->
        handle_start_timer(command_release_attempt_id, app_state, ctx)

      {:completion, command_release_attempt_id} ->
        handle_completion_timer(command_release_attempt_id, app_state, ctx)

      :unknown ->
        {:error, {:unknown_transport_timer, timer_key}}
    end
  end

  def handle_timer(timer_key, _app_state, %ExecutionContext{}) do
    {:error, {:unknown_transport_timer, timer_key}}
  end

  @impl true
  def snapshot_state(app_state, %ExecutionContext{}) when is_map(app_state) do
    {:ok, app_state}
  end

  def snapshot_state(app_state, %ExecutionContext{}) do
    {:error, {:invalid_uplink_gateway_state, app_state}}
  end

  defp normalize_configuration(%{} = configuration) do
    {:ok,
     %{
       service_name: config_value(configuration, :service_name, "service_name"),
       transport_profile:
         normalize_transport_profile(
           config_value(configuration, :transport_profile, "transport_profile")
         ),
       frame_size: configured_frame_size(configuration),
       scid: config_value_or_default(configuration, :scid, "scid", 0),
       vcid: config_value_or_default(configuration, :vcid, "vcid", 0),
       bypass_flag: config_value_or_default(configuration, :bypass_flag, "bypass_flag", 0),
       control_command_flag:
         config_value_or_default(
           configuration,
           :control_command_flag,
           "control_command_flag",
           0
         ),
       segment_header_flag:
         config_value_or_default(
           configuration,
           :segment_header_flag,
           "segment_header_flag",
           0
         ),
       initial_frame_seq:
         config_value_or_default(configuration, :initial_frame_seq, "initial_frame_seq", 0),
       cop1_mode: normalize_cop1_mode(config_value(configuration, :cop1_mode, "cop1_mode")),
       cop1_timeout_ms:
         config_value_or_default(
           configuration,
           :cop1_timeout_ms,
           "cop1_timeout_ms",
           @default_cop1_timeout_ms
         ),
       cop1_max_retransmit:
         config_value_or_default(
           configuration,
           :cop1_max_retransmit,
           "cop1_max_retransmit",
           @default_cop1_max_retransmit
         ),
       cop1_window_size:
         config_value_or_default(configuration, :cop1_window_size, "cop1_window_size", 1),
       simulated_start_delay_ms:
         config_value(
           configuration,
           :simulated_start_delay_ms,
           "simulated_start_delay_ms"
         ),
       simulated_completion_delay_ms:
         config_value(
           configuration,
           :simulated_completion_delay_ms,
           "simulated_completion_delay_ms"
         ),
       provider_binding_id:
         provider_config_value(configuration, :provider_binding_id, "provider_binding_id"),
       provider_adapter_key:
         normalize_provider_adapter_key(
           provider_config_value(configuration, :provider_adapter_key, "provider_adapter_key")
         )
     }}
  end

  defp normalize_configuration(configuration) do
    {:error, {:unsupported_uplink_gateway_configuration, configuration}}
  end

  defp configured_frame_size(configuration) do
    config_value(configuration, :frame_size, "frame_size") ||
      config_value(configuration, :tc_frame_size, "tc_frame_size") ||
      @default_frame_size
  end

  defp config_value_or_default(configuration, atom_key, string_key, default) do
    config_value(configuration, atom_key, string_key) || default
  end

  defp validate_configuration(normalized_configuration) when is_map(normalized_configuration) do
    with :ok <- validate_transport_profile(normalized_configuration.transport_profile),
         :ok <- validate_frame_size(normalized_configuration.frame_size),
         :ok <- validate_range(normalized_configuration.scid, 0, 1023, :scid),
         :ok <- validate_range(normalized_configuration.vcid, 0, 63, :vcid),
         :ok <- validate_flag(normalized_configuration.bypass_flag, :bypass_flag),
         :ok <-
           validate_flag(
             normalized_configuration.control_command_flag,
             :control_command_flag
           ),
         :ok <-
           validate_flag(
             normalized_configuration.segment_header_flag,
             :segment_header_flag
           ),
         :ok <-
           validate_range(
             normalized_configuration.initial_frame_seq,
             0,
             255,
             :initial_frame_seq
           ),
         :ok <- validate_cop1_mode(normalized_configuration.cop1_mode),
         :ok <-
           validate_positive_integer(normalized_configuration.cop1_timeout_ms, :cop1_timeout_ms),
         :ok <-
           validate_non_negative_integer(
             normalized_configuration.cop1_max_retransmit,
             :cop1_max_retransmit
           ),
         :ok <- validate_cop1_window_size(normalized_configuration.cop1_window_size),
         :ok <- validate_optional_delay(normalized_configuration.simulated_start_delay_ms),
         :ok <- validate_optional_delay(normalized_configuration.simulated_completion_delay_ms) do
      validate_provider_configuration(
        normalized_configuration.provider_binding_id,
        normalized_configuration.provider_adapter_key
      )
    end
  end

  defp config_value(configuration, atom_key, string_key) do
    cond do
      Map.has_key?(configuration, atom_key) -> Map.get(configuration, atom_key)
      Map.has_key?(configuration, string_key) -> Map.get(configuration, string_key)
      true -> nil
    end
  end

  defp provider_config_value(configuration, atom_key, string_key) do
    case config_value(configuration, :provider, "provider") do
      provider when is_map(provider) ->
        config_value(provider, atom_key, string_key) ||
          config_value(configuration, atom_key, string_key)

      _other ->
        config_value(configuration, atom_key, string_key)
    end
  end

  defp build_cop1_state(:fop, vcid, timeout_ms, max_retransmit) do
    FOP.new(%{
      enabled: true,
      vcid: vcid,
      timeout_ms: timeout_ms,
      max_retransmit: max_retransmit
    })
  end

  defp build_cop1_state(_mode, _vcid, _timeout_ms, _max_retransmit), do: nil

  defp cop1_enabled?(app_state) when is_map(app_state), do: app_state.cop1_mode == :fop

  defp accepts_service?(nil, _preferred_uplink_service), do: true
  defp accepts_service?(service_name, nil) when is_binary(service_name), do: true
  defp accepts_service?(service_name, service_name) when is_binary(service_name), do: true
  defp accepts_service?(_service_name, _preferred_uplink_service), do: false

  defp normalize_transport_profile(nil), do: @default_transport_profile
  defp normalize_transport_profile(:tc), do: :tc
  defp normalize_transport_profile("tc"), do: :tc
  defp normalize_transport_profile(other), do: other

  defp normalize_cop1_mode(nil), do: :disabled
  defp normalize_cop1_mode(:disabled), do: :disabled
  defp normalize_cop1_mode("disabled"), do: :disabled
  defp normalize_cop1_mode(:fop), do: :fop
  defp normalize_cop1_mode("fop"), do: :fop
  defp normalize_cop1_mode(other), do: other

  defp normalize_provider_adapter_key(nil), do: nil
  defp normalize_provider_adapter_key(:tcp_socket), do: :tcp_socket
  defp normalize_provider_adapter_key("tcp_socket"), do: :tcp_socket
  defp normalize_provider_adapter_key(other), do: other

  defp validate_transport_profile(:tc), do: :ok

  defp validate_transport_profile(profile),
    do: {:error, {:unsupported_uplink_gateway_transport_profile, profile}}

  defp validate_cop1_mode(mode) when mode in [:disabled, :fop], do: :ok
  defp validate_cop1_mode(mode), do: {:error, {:unsupported_uplink_gateway_cop1_mode, mode}}

  defp validate_frame_size(frame_size) when is_integer(frame_size) and frame_size > 5, do: :ok

  defp validate_frame_size(frame_size),
    do: {:error, {:invalid_uplink_gateway_frame_size, frame_size}}

  defp validate_positive_integer(value, _field) when is_integer(value) and value > 0, do: :ok

  defp validate_positive_integer(value, field),
    do: {:error, {:invalid_uplink_gateway_field, field, value}}

  defp validate_non_negative_integer(value, _field) when is_integer(value) and value >= 0, do: :ok

  defp validate_non_negative_integer(value, field),
    do: {:error, {:invalid_uplink_gateway_field, field, value}}

  defp validate_cop1_window_size(1), do: :ok

  defp validate_cop1_window_size(value),
    do: {:error, {:unsupported_uplink_gateway_cop1_window_size, value}}

  defp validate_optional_delay(nil), do: :ok
  defp validate_optional_delay(delay_ms) when is_integer(delay_ms) and delay_ms > 0, do: :ok

  defp validate_optional_delay(delay_ms),
    do: {:error, {:invalid_uplink_gateway_delay_ms, delay_ms}}

  defp validate_provider_configuration(nil, nil), do: :ok

  defp validate_provider_configuration(provider_binding_id, provider_adapter_key)
       when is_binary(provider_binding_id) and provider_binding_id != "" and
              provider_adapter_key == :tcp_socket,
       do: :ok

  defp validate_provider_configuration(provider_binding_id, provider_adapter_key) do
    {:error,
     {:invalid_uplink_gateway_provider_configuration, provider_binding_id, provider_adapter_key}}
  end

  defp validate_flag(value, _field) when value in [0, 1], do: :ok
  defp validate_flag(value, field), do: {:error, {:invalid_uplink_gateway_flag, field, value}}

  defp validate_range(value, min, max, _field)
       when is_integer(value) and value >= min and value <= max,
       do: :ok

  defp validate_range(value, _min, _max, field),
    do: {:error, {:invalid_uplink_gateway_field, field, value}}

  defp cop1_strategy(app_state, %UplinkRequest{} = framed_uplink_request) do
    if cop1_enabled?(app_state) and not bypass_mode?(framed_uplink_request) do
      :fop
    else
      :direct
    end
  end

  defp bypass_mode?(%UplinkRequest{} = uplink_request) do
    uplink_request.bypass_flag == 1 or uplink_request.control_command_flag == 1
  end

  defp frame_uplink_request(%UplinkRequest{} = uplink_request, app_state, current_time) do
    with {:ok, encoded_command} <- Base.decode64(uplink_request.encoded_binary_base64),
         {:ok, segmentation_state} <- Segmentation.init(frame_seq: app_state.next_frame_seq),
         sdu <- build_sdu(encoded_command, uplink_request, app_state, current_time),
         {:ok, frames, next_segmentation_state} <-
           Segmentation.segment(
             sdu,
             %{
               frame_size: app_state.frame_size,
               scid: app_state.scid,
               vcid: app_state.vcid,
               bypass_flag: app_state.bypass_flag,
               control_command_flag: app_state.control_command_flag,
               segment_header_flag: app_state.segment_header_flag
             },
             segmentation_state
           ),
         {:ok, transfer_frames} <- encode_transfer_frames(frames, app_state.frame_size) do
      {:ok, enrich_uplink_request(uplink_request, transfer_frames, frames, app_state),
       next_segmentation_state.frame_seq}
    else
      :error ->
        {:error, {:invalid_uplink_request_payload, :base64}}

      {:error, reason, _state} ->
        {:error, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_sdu(encoded_command, uplink_request, app_state, current_time) do
    %SDUOctets{
      profile: app_state.transport_profile,
      scid: app_state.scid,
      vcid: app_state.vcid,
      map_id: nil,
      direction: :uplink,
      sdu_kind_hint: uplink_request.layout_kind || :command,
      octets: encoded_command,
      quality: :good,
      source_frames: [],
      timestamp: current_time,
      meta: %{
        command_release_attempt_id: uplink_request.command_release_attempt_id,
        command_request_id: uplink_request.command_request_id,
        command_name: uplink_request.command_name
      }
    }
  end

  defp encode_transfer_frames(frames, frame_size) when is_list(frames) do
    Enum.reduce_while(frames, {:ok, []}, fn frame, {:ok, acc} ->
      case FrameCodec.encode(frame, frame_size: frame_size) do
        {:ok, transfer_frame} -> {:cont, {:ok, [transfer_frame | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, transfer_frames} -> {:ok, Enum.reverse(transfer_frames)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp enrich_uplink_request(
         %UplinkRequest{} = uplink_request,
         transfer_frames,
         frames,
         app_state
       ) do
    frame_sequences =
      frames
      |> Enum.map(& &1.frame_seq)
      |> Enum.filter(&is_integer/1)

    %UplinkRequest{
      uplink_request
      | transport_profile: app_state.transport_profile,
        transfer_frames_base64: Enum.map(transfer_frames, &Base.encode64/1),
        transfer_frame_count: length(transfer_frames),
        transfer_frame_size_bytes: app_state.frame_size,
        first_frame_seq: List.first(frame_sequences),
        last_frame_seq: List.last(frame_sequences),
        scid: app_state.scid,
        vcid: app_state.vcid,
        bypass_flag: app_state.bypass_flag,
        control_command_flag: app_state.control_command_flag,
        segment_header_flag: app_state.segment_header_flag
    }
  end

  defp handle_cop1_release(
         framed_uplink_request,
         app_state,
         next_frame_seq,
         %ExecutionContext{} = ctx
       ) do
    with {:ok, frame_entries} <- frame_entries_from_request(framed_uplink_request),
         {:ok, transition} <-
           FOP.accept_release(
             app_state.cop1,
             Map.from_struct(framed_uplink_request),
             frame_entries
           ) do
      {:ok,
       build_cop1_execution_result(
         %{app_state | next_frame_seq: next_frame_seq},
         transition,
         ctx.current_time,
         next_frame_seq
       )}
    end
  end

  defp handle_cop1_timeout(
         command_release_attempt_id,
         seq,
         %{cop1: %FOP{in_flight_release: %{metadata: metadata}}} = app_state,
         %ExecutionContext{} = ctx
       ) do
    if metadata.command_release_attempt_id != command_release_attempt_id do
      {:ok, ExecutionResult.new(%{state: app_state})}
    else
      with {:ok, transition} <- FOP.handle_timeout(app_state.cop1, seq) do
        {:ok, build_cop1_execution_result(app_state, transition, ctx.current_time)}
      end
    end
  end

  defp handle_cop1_timeout(_command_release_attempt_id, _seq, app_state, %ExecutionContext{}) do
    {:ok, ExecutionResult.new(%{state: app_state})}
  end

  defp build_cop1_execution_result(app_state, transition, current_time, next_frame_seq \\ nil) do
    state = transition.state
    transition_metadata = transition_signal_metadata(transition.signal)
    metadata = cop1_transition_metadata(app_state, state, transition.signal, transition_metadata)
    started_increment = cop1_signal_increment(transition.signal, :start)
    completed_increment = cop1_signal_increment(transition.signal, :completion)

    %ExecutionResult{
      state: %{
        app_state
        | cop1: state,
          next_frame_seq: next_frame_seq || app_state.next_frame_seq,
          accepted_uplink_count:
            app_state.accepted_uplink_count + length(transition.transmit_frames),
          started_uplink_count: app_state.started_uplink_count + started_increment,
          completed_uplink_count: app_state.completed_uplink_count + completed_increment,
          last_release_attempt_id:
            metadata[:command_release_attempt_id] || app_state.last_release_attempt_id,
          last_command_request_id:
            metadata[:command_request_id] || app_state.last_command_request_id,
          last_command_name: metadata[:command_name] || app_state.last_command_name,
          last_signal_phase: metadata[:signal_phase] || app_state.last_signal_phase,
          last_signal_at:
            if(metadata[:signal_phase], do: current_time, else: app_state.last_signal_at),
          last_control_at: current_time
      },
      action_requests:
        build_cop1_action_requests(app_state, state, transition.transmit_frames) ++
          build_cop1_timer_actions(transition, metadata),
      metadata: metadata
    }
  end

  defp cop1_transition_metadata(app_state, state, signal, transition_metadata) do
    release_metadata =
      current_cop1_release_metadata(state) || current_cop1_release_metadata(app_state.cop1)

    signal
    |> case do
      nil -> release_metadata || %{}
      _other -> Map.merge(release_metadata || %{}, transition_metadata)
    end
  end

  defp cop1_signal_increment({signal_phase, _metadata}, signal_phase), do: 1
  defp cop1_signal_increment(_signal, _signal_phase), do: 0

  defp build_direct_execution_result(
         %UplinkRequest{} = framed_uplink_request,
         app_state,
         next_frame_seq,
         current_time
       ) do
    release_metadata = release_metadata(framed_uplink_request)
    track_release? = track_release?(app_state)

    ExecutionResult.new(%{
      state: %{
        app_state
        | active_releases:
            maybe_track_release(
              app_state.active_releases,
              track_release?,
              %{
                command_release_attempt_id: framed_uplink_request.command_release_attempt_id,
                command_request_id: framed_uplink_request.command_request_id,
                command_name: framed_uplink_request.command_name,
                source_endpoint_ref: framed_uplink_request.source_endpoint_ref,
                completion_delay_ms: app_state.simulated_completion_delay_ms
              }
            ),
          next_frame_seq: next_frame_seq,
          accepted_uplink_count: app_state.accepted_uplink_count + 1,
          last_release_attempt_id: framed_uplink_request.command_release_attempt_id,
          last_command_request_id: framed_uplink_request.command_request_id,
          last_command_name: framed_uplink_request.command_name,
          last_signal_phase: :acceptance,
          last_signal_at: current_time,
          last_control_at: current_time
      },
      action_requests:
        [framed_uplink_request] ++
          provider_action_requests(app_state, framed_uplink_request) ++
          scheduled_follow_up_actions(
            framed_uplink_request.command_release_attempt_id,
            app_state.simulated_start_delay_ms,
            app_state.simulated_completion_delay_ms,
            release_metadata
          )
    })
  end

  defp frame_entries_from_request(%UplinkRequest{} = framed_uplink_request) do
    transfer_frames = framed_uplink_request.transfer_frames_base64
    transfer_frame_count = framed_uplink_request.transfer_frame_count || length(transfer_frames)
    first_frame_seq = framed_uplink_request.first_frame_seq

    cond do
      transfer_frames == [] ->
        {:error, :missing_framed_uplink_transfer_frames}

      not is_integer(first_frame_seq) ->
        {:error, :missing_framed_uplink_first_frame_seq}

      transfer_frame_count != length(transfer_frames) ->
        {:error, :invalid_framed_uplink_transfer_frame_count}

      true ->
        frame_entries =
          transfer_frames
          |> Enum.with_index()
          |> Enum.map(fn {frame_base64, index} ->
            %{
              seq: rem(first_frame_seq + index, 256),
              frame_base64: frame_base64
            }
          end)

        {:ok, frame_entries}
    end
  end

  defp build_cop1_action_requests(app_state, cop1_state, frame_entries) do
    case cop1_state.in_flight_release do
      %{base_request: base_request} ->
        Enum.flat_map(frame_entries, fn frame_entry ->
          framed_uplink_request =
            frame_uplink_request_from_entry(base_request, app_state, frame_entry)

          [framed_uplink_request] ++ provider_action_requests(app_state, framed_uplink_request)
        end)

      nil ->
        []
    end
  end

  defp provider_action_requests(
         %{provider_binding_id: provider_binding_id, provider_adapter_key: provider_adapter_key},
         %UplinkRequest{} = framed_uplink_request
       )
       when is_binary(provider_binding_id) and is_atom(provider_adapter_key) do
    [
      ProviderRequest.new(%{
        provider_binding_id: provider_binding_id,
        provider_adapter_key: provider_adapter_key,
        command_release_attempt_id: framed_uplink_request.command_release_attempt_id,
        command_queue_entry_id: framed_uplink_request.command_queue_entry_id,
        command_request_id: framed_uplink_request.command_request_id,
        source_endpoint_ref: framed_uplink_request.source_endpoint_ref,
        command_snapshot_id: framed_uplink_request.command_snapshot_id,
        command_id: framed_uplink_request.command_id,
        command_name: framed_uplink_request.command_name,
        transport_profile: framed_uplink_request.transport_profile,
        payloads_base64: framed_uplink_request.transfer_frames_base64,
        payload_count:
          framed_uplink_request.transfer_frame_count ||
            length(framed_uplink_request.transfer_frames_base64),
        payload_size_bytes: framed_uplink_request.transfer_frame_size_bytes,
        metadata: framed_uplink_request.metadata
      })
    ]
  end

  defp provider_action_requests(_app_state, %UplinkRequest{}), do: []

  defp frame_uplink_request_from_entry(base_request, app_state, frame_entry) do
    release_kind =
      if frame_entry.retries == 0 do
        :initial
      else
        :retransmit
      end

    UplinkRequest.new(%{
      command_release_attempt_id: base_request.command_release_attempt_id,
      command_queue_entry_id: base_request.command_queue_entry_id,
      command_request_id: base_request.command_request_id,
      source_endpoint_ref: base_request.source_endpoint_ref,
      command_snapshot_id: base_request.command_snapshot_id,
      command_id: base_request.command_id,
      command_name: base_request.command_name,
      layout_kind: base_request.layout_kind,
      preferred_uplink_service: base_request.preferred_uplink_service,
      apid: base_request.apid,
      service_type: base_request.service_type,
      service_subtype: base_request.service_subtype,
      opcode: base_request.opcode,
      encoded_binary_base64: base_request.encoded_binary_base64,
      encoded_size_bytes: base_request.encoded_size_bytes,
      transport_profile: app_state.transport_profile,
      transfer_frames_base64: [frame_entry.frame_base64],
      transfer_frame_count: 1,
      transfer_frame_size_bytes: app_state.frame_size,
      first_frame_seq: frame_entry.seq,
      last_frame_seq: frame_entry.seq,
      scid: app_state.scid,
      vcid: app_state.vcid,
      bypass_flag: app_state.bypass_flag,
      control_command_flag: app_state.control_command_flag,
      segment_header_flag: app_state.segment_header_flag,
      metadata:
        Map.merge(Map.get(base_request, :metadata, %{}), %{
          "cop1_release_kind" => Atom.to_string(release_kind),
          "cop1_retry_count" => frame_entry.retries
        })
    })
  end

  defp build_cop1_timer_actions(transition, release_metadata) do
    schedule_timers =
      case release_metadata do
        %{command_release_attempt_id: command_release_attempt_id} ->
          Enum.map(transition.schedule_timeout_seqs, fn seq ->
            ScheduleTimer.new(%{
              timer_key: cop1_timeout_timer_key(command_release_attempt_id, seq),
              delay_ms: transition.state.timeout_ms,
              metadata: Map.put(release_metadata, :frame_seq, seq)
            })
          end)

        _other ->
          []
      end

    cancel_timers =
      case release_metadata do
        %{command_release_attempt_id: command_release_attempt_id} ->
          Enum.map(transition.cancel_timeout_seqs, fn seq ->
            CancelTimer.new(%{
              timer_key: cop1_timeout_timer_key(command_release_attempt_id, seq)
            })
          end)

        nil ->
          []
      end

    cancel_timers ++ schedule_timers
  end

  defp current_cop1_release_metadata(%FOP{in_flight_release: %{metadata: metadata}})
       when is_map(metadata),
       do: metadata

  defp current_cop1_release_metadata(_cop1_state), do: nil

  defp cop1_timeout_timer_key(command_release_attempt_id, seq)
       when is_binary(command_release_attempt_id) and is_integer(seq) do
    @cop1_timeout_timer_prefix <> command_release_attempt_id <> ":" <> Integer.to_string(seq)
  end

  defp transition_signal_metadata(nil), do: %{}

  defp transition_signal_metadata({signal_phase, metadata})
       when signal_phase in [:start, :completion] and is_map(metadata) do
    metadata
    |> Map.new()
    |> Map.put(:signal_phase, signal_phase)
  end

  defp normalize_cop1_clcw_event(%CLCW{} = clcw), do: {:ok, clcw}
  defp normalize_cop1_clcw_event({:cop1_clcw, %CLCW{} = clcw}), do: {:ok, clcw}

  defp normalize_cop1_clcw_event(%{kind: :cop1_clcw, clcw: %CLCW{} = clcw}),
    do: {:ok, clcw}

  defp normalize_cop1_clcw_event(%{"kind" => "cop1_clcw", "clcw_base64" => clcw_base64})
       when is_binary(clcw_base64) do
    with {:ok, clcw_binary} <- Base.decode64(clcw_base64),
         {:ok, %CLCW{} = clcw} <- CLCW.decode(clcw_binary) do
      {:ok, clcw}
    else
      :error -> {:error, {:invalid_cop1_clcw_event, :base64}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_cop1_clcw_event(%{kind: :cop1_clcw, clcw_binary: clcw_binary})
       when is_binary(clcw_binary) do
    CLCW.decode(clcw_binary)
  end

  defp normalize_cop1_clcw_event(_event), do: {:error, :not_cop1_clcw_event}

  defp maybe_schedule_start_timer(command_release_attempt_id, delay_ms, release_metadata)
       when is_binary(command_release_attempt_id) and is_integer(delay_ms) and delay_ms > 0 do
    [
      ScheduleTimer.new(%{
        timer_key: @start_timer_prefix <> command_release_attempt_id,
        delay_ms: delay_ms,
        metadata: Map.put(release_metadata, :signal_phase, :start)
      })
    ]
  end

  defp maybe_schedule_completion_timer(delay_ms, release_metadata)
       when is_integer(delay_ms) and delay_ms > 0 do
    [
      ScheduleTimer.new(%{
        timer_key: @completion_timer_prefix <> release_metadata.command_release_attempt_id,
        delay_ms: delay_ms,
        metadata: Map.put(release_metadata, :signal_phase, :completion)
      })
    ]
  end

  defp handle_start_timer(command_release_attempt_id, app_state, %ExecutionContext{} = ctx) do
    case Map.get(app_state.active_releases, command_release_attempt_id) do
      nil ->
        {:error, {:unknown_uplink_release_attempt, command_release_attempt_id}}

      release_state ->
        {active_releases, completion_action_requests} =
          case release_state.completion_delay_ms do
            delay_ms when is_integer(delay_ms) and delay_ms > 0 ->
              {app_state.active_releases,
               maybe_schedule_completion_timer(
                 delay_ms,
                 %{
                   command_release_attempt_id: release_state.command_release_attempt_id,
                   command_request_id: release_state.command_request_id,
                   command_name: release_state.command_name,
                   source_endpoint_ref: release_state.source_endpoint_ref
                 }
               )}

            _other ->
              {Map.delete(app_state.active_releases, command_release_attempt_id), []}
          end

        {:ok,
         ExecutionResult.new(%{
           state: %{
             app_state
             | active_releases: active_releases,
               started_uplink_count: app_state.started_uplink_count + 1,
               last_release_attempt_id: release_state.command_release_attempt_id,
               last_command_request_id: release_state.command_request_id,
               last_command_name: release_state.command_name,
               last_signal_phase: :start,
               last_signal_at: ctx.current_time
           },
           action_requests: completion_action_requests
         })}
    end
  end

  defp handle_completion_timer(command_release_attempt_id, app_state, %ExecutionContext{} = ctx) do
    case Map.pop(app_state.active_releases, command_release_attempt_id) do
      {nil, _active_releases} ->
        {:error, {:unknown_uplink_release_attempt, command_release_attempt_id}}

      {release_state, active_releases} ->
        {:ok,
         ExecutionResult.new(%{
           state: %{
             app_state
             | active_releases: active_releases,
               completed_uplink_count: app_state.completed_uplink_count + 1,
               last_release_attempt_id: release_state.command_release_attempt_id,
               last_command_request_id: release_state.command_request_id,
               last_command_name: release_state.command_name,
               last_signal_phase: :completion,
               last_signal_at: ctx.current_time
           }
         })}
    end
  end

  defp parse_timer_key(@start_timer_prefix <> command_release_attempt_id),
    do: {:start, command_release_attempt_id}

  defp parse_timer_key(@completion_timer_prefix <> command_release_attempt_id),
    do: {:completion, command_release_attempt_id}

  defp parse_timer_key(@cop1_timeout_timer_prefix <> tail) do
    case String.split(tail, ":", parts: 2) do
      [command_release_attempt_id, seq_string] ->
        case Integer.parse(seq_string) do
          {seq, ""} -> {:cop1_timeout, command_release_attempt_id, seq}
          _other -> :unknown
        end

      _other ->
        :unknown
    end
  end

  defp parse_timer_key(_timer_key), do: :unknown

  defp release_metadata(%UplinkRequest{} = uplink_request) do
    %{
      command_release_attempt_id: uplink_request.command_release_attempt_id,
      command_request_id: uplink_request.command_request_id,
      command_name: uplink_request.command_name,
      source_endpoint_ref: uplink_request.source_endpoint_ref
    }
  end

  defp track_release?(app_state) when is_map(app_state) do
    not cop1_enabled?(app_state) and
      (is_integer(app_state.simulated_start_delay_ms) or
         is_integer(app_state.simulated_completion_delay_ms))
  end

  defp maybe_track_release(active_releases, false, _release_state) when is_map(active_releases),
    do: active_releases

  defp maybe_track_release(active_releases, true, release_state) when is_map(active_releases) do
    Map.put(active_releases, release_state.command_release_attempt_id, release_state)
  end

  defp scheduled_follow_up_actions(
         command_release_attempt_id,
         simulated_start_delay_ms,
         simulated_completion_delay_ms,
         release_metadata
       ) do
    cond do
      is_integer(simulated_start_delay_ms) and simulated_start_delay_ms > 0 ->
        maybe_schedule_start_timer(
          command_release_attempt_id,
          simulated_start_delay_ms,
          release_metadata
        )

      is_integer(simulated_completion_delay_ms) and simulated_completion_delay_ms > 0 ->
        maybe_schedule_completion_timer(simulated_completion_delay_ms, release_metadata)

      true ->
        []
    end
  end
end
