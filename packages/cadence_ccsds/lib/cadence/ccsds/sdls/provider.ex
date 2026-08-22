defmodule Cadence.CCSDS.SDLS.Provider do
  @moduledoc """
  Pure CCSDS 355.0-B-2 ApplySecurity and ProcessSecurity provider.

  The provider owns Security Association selection, wire fields, authentication
  masking, anti-replay transitions, and verification evidence. Cryptographic
  operations and opaque key references are delegated to a callback module.
  """

  import Bitwise

  alias Cadence.CCSDS.SDLS.{
    AntiReplay,
    ApplyRequest,
    ApplyResult,
    AuthenticationMask,
    Channel,
    Operation,
    ProcessRequest,
    ProcessResult,
    SecurityAssociation,
    SecurityHeader,
    Service,
    Verification
  }

  alias Cadence.CCSDS.SDLS.Provider.Receiver

  @required_callbacks [
    {:padding_length, 3},
    {:encrypt, 3},
    {:decrypt, 3},
    {:authenticate, 3}
  ]

  @type association_key :: {binary(), 1..65_534}
  @type dynamic_state :: %{
          sequence_number: non_neg_integer(),
          initialization_vector: binary()
        }

  @type t :: %__MODULE__{
          associations: %{required(association_key()) => SecurityAssociation.t()},
          outbound_by_channel: %{required(tuple()) => association_key()},
          sender_state: %{required(association_key()) => dynamic_state()},
          receiver_state: %{required(association_key()) => dynamic_state()},
          crypto_provider: module(),
          crypto_state: term()
        }

  defstruct associations: %{},
            outbound_by_channel: %{},
            sender_state: %{},
            receiver_state: %{},
            crypto_provider: nil,
            crypto_state: nil

  @spec init([SecurityAssociation.t()], module(), keyword()) :: {:ok, t()} | {:error, term()}
  def init(associations, crypto_provider, opts \\ [])
      when is_list(associations) and is_atom(crypto_provider) and is_list(opts) do
    with :ok <- validate_crypto_provider(crypto_provider),
         {:ok, indexed} <- index_associations(associations),
         {:ok, outbound} <- index_outbound_channels(indexed) do
      dynamic = Map.new(indexed, fn {key, association} -> {key, initial_state(association)} end)

      {:ok,
       %__MODULE__{
         associations: indexed,
         outbound_by_channel: outbound,
         sender_state: dynamic,
         receiver_state: dynamic,
         crypto_provider: crypto_provider,
         crypto_state: Keyword.get(opts, :crypto_state)
       }}
    end
  end

  @spec apply_security(ApplyRequest.t(), t()) ::
          {:ok, ApplyResult.t(), t()} | {:error, term(), t()}
  def apply_security(%ApplyRequest{} = request, %__MODULE__{} = state) do
    case do_apply_security(request, state) do
      {:ok, result, next_state} -> {:ok, result, next_state}
      {:error, reason} -> {:error, reason, state}
    end
  end

  def apply_security(value, %__MODULE__{} = state),
    do: {:error, {:invalid_apply_security_request, value}, state}

  @spec process_security(ProcessRequest.t(), t()) ::
          {:ok, ProcessResult.t(), t()} | {:error, Verification.t(), t()}
  def process_security(%ProcessRequest{} = request, %__MODULE__{} = state) do
    case Receiver.process(request, state) do
      {:ok, result, next_state} ->
        {:ok, result, next_state}

      {:verification_error, code, reason, spi} ->
        {:error, failure(code, reason, spi), state}
    end
  end

  def process_security(value, %__MODULE__{} = state) do
    verification = failure(:malformed_security_header, {:invalid_process_security_request, value})
    {:error, verification, state}
  end

  @spec dynamic_state(t(), :sender | :receiver, binary(), 1..65_534) ::
          {:ok, dynamic_state()} | {:error, :unknown_security_association}
  def dynamic_state(%__MODULE__{} = state, direction, physical_channel, spi)
      when direction in [:sender, :receiver] and is_binary(physical_channel) do
    states = if(direction == :sender, do: state.sender_state, else: state.receiver_state)

    case Map.fetch(states, {physical_channel, spi}) do
      {:ok, dynamic} -> {:ok, dynamic}
      :error -> {:error, :unknown_security_association}
    end
  end

  defp do_apply_security(request, state) do
    with :ok <- validate_apply_request(request),
         {:ok, key, association} <- fetch_outbound_association(request.channel, state),
         :ok <-
           Service.validate(request.channel, request.service, association.service_type),
         dynamic <- Map.fetch!(state.sender_state, key),
         {:ok, header, staged_dynamic} <- outbound_header(association, dynamic),
         operation <- operation(request, association, header),
         {:ok, pad_length, crypto_state} <- padding_length(request.data, operation, state),
         header <- %{header | pad_length: pad_length},
         {:ok, encoded_header} <- SecurityHeader.encode(header, association),
         operation <- %{operation | security_header: encoded_header, pad_length: pad_length},
         {:ok, protected_data, next_iv, crypto_state} <-
           encrypt_data(request.data, operation, crypto_state, state),
         {:ok, mac, crypto_state} <-
           outbound_mac(
             request.frame_prefix,
             encoded_header,
             protected_data,
             operation,
             crypto_state,
             state
           ),
         next_dynamic <- outbound_dynamic(staged_dynamic, next_iv, association),
         result <- apply_result(request, association, header, encoded_header, protected_data, mac),
         next_state <-
           %{
             state
             | sender_state: Map.put(state.sender_state, key, next_dynamic),
               crypto_state: crypto_state
           } do
      {:ok, result, next_state}
    end
  end

  defp outbound_header(association, dynamic) do
    case association.sequence_number_source do
      :sequence_number -> sequence_header(association, dynamic)
      :initialization_vector -> iv_sequence_header(association, dynamic)
      nil -> unnumbered_header(association, dynamic)
    end
  end

  defp sequence_header(association, dynamic) do
    with {:ok, sequence} <-
           AntiReplay.next(dynamic.sequence_number, association.sequence_number_length) do
      header = %SecurityHeader{
        spi: association.spi,
        initialization_vector: dynamic.initialization_vector,
        sequence_number: sequence
      }

      {:ok, header, %{dynamic | sequence_number: sequence}}
    end
  end

  defp iv_sequence_header(association, dynamic) do
    with {:ok, iv} <- AntiReplay.next_binary(dynamic.initialization_vector) do
      sequence = :binary.decode_unsigned(iv)
      header = %SecurityHeader{spi: association.spi, initialization_vector: iv}
      {:ok, header, %{dynamic | sequence_number: sequence, initialization_vector: iv}}
    end
  end

  defp unnumbered_header(association, dynamic) do
    header = %SecurityHeader{
      spi: association.spi,
      initialization_vector: dynamic.initialization_vector
    }

    {:ok, header, dynamic}
  end

  defp operation(request, association, header) do
    %Operation{
      direction: :outbound,
      channel: request.channel,
      service: request.service,
      association: association,
      frame_prefix: request.frame_prefix,
      security_header: <<>>,
      initialization_vector: header.initialization_vector,
      sequence_number: header.sequence_number,
      pad_length: header.pad_length,
      meta: request.meta
    }
  end

  defp padding_length(_data, %Operation{association: %{pad_length_length: 0}}, state),
    do: {:ok, 0, state.crypto_state}

  defp padding_length(data, operation, state) do
    case state.crypto_provider.padding_length(data, operation, state.crypto_state) do
      {:ok, pad_length, crypto_state} ->
        validate_padding_length(pad_length, operation, crypto_state)

      {:error, reason} ->
        {:error, {:crypto_provider_error, :padding_length, reason}}

      returned ->
        {:error, {:invalid_crypto_provider_return, :padding_length, returned}}
    end
  end

  defp validate_padding_length(pad_length, operation, crypto_state) do
    maximum = (1 <<< (operation.association.pad_length_length * 8)) - 1

    if is_integer(pad_length) and pad_length >= 0 and pad_length <= maximum,
      do: {:ok, pad_length, crypto_state},
      else: {:error, {:invalid_crypto_padding_length, pad_length, maximum}}
  end

  defp encrypt_data(data, %Operation{association: association}, crypto_state, _state)
       when association.service_type == :authentication,
       do: {:ok, data, association.initialization_vector, crypto_state}

  defp encrypt_data(data, operation, crypto_state, state) do
    case state.crypto_provider.encrypt(data, operation, crypto_state) do
      {:ok, protected_data, next_iv, next_crypto_state} ->
        with :ok <- validate_binary(protected_data, :protected_data),
             :ok <- validate_iv(next_iv, operation.association) do
          {:ok, protected_data, next_iv, next_crypto_state}
        end

      {:error, reason} ->
        {:error, {:crypto_provider_error, :encrypt, reason}}

      returned ->
        {:error, {:invalid_crypto_provider_return, :encrypt, returned}}
    end
  end

  defp outbound_mac(_prefix, _header, _data, %{association: association}, crypto_state, _state)
       when association.service_type == :encryption,
       do: {:ok, <<>>, crypto_state}

  defp outbound_mac(prefix, header, data, operation, crypto_state, state) do
    payload = prefix <> header <> data

    with {:ok, masked} <-
           AuthenticationMask.apply(
             payload,
             prefix,
             operation.channel,
             operation.service,
             operation.association
           ),
         {:ok, mac, next_crypto_state} <-
           authenticate(masked, operation, crypto_state, state),
         {:ok, transmitted_mac} <- truncate_mac(mac, operation.association.mac_length) do
      {:ok, transmitted_mac, next_crypto_state}
    end
  end

  defp authenticate(payload, operation, crypto_state, state) do
    case state.crypto_provider.authenticate(payload, operation, crypto_state) do
      {:ok, mac, next_crypto_state} when is_binary(mac) ->
        {:ok, mac, next_crypto_state}

      {:error, reason} ->
        {:error, {:crypto_provider_error, {:authenticate, :outbound}, reason}}

      returned ->
        {:error, {:invalid_crypto_provider_return, {:authenticate, :outbound}, returned}}
    end
  end

  defp truncate_mac(mac, length) when is_binary(mac) and byte_size(mac) >= length,
    do: {:ok, binary_part(mac, 0, length)}

  defp truncate_mac(mac, length),
    do: {:error, {:authentication_code_too_short, byte_size_safe(mac), length}}

  defp outbound_dynamic(dynamic, next_iv, association) do
    if SecurityAssociation.encryption?(association) and
         association.sequence_number_source != :initialization_vector do
      %{dynamic | initialization_vector: next_iv}
    else
      dynamic
    end
  end

  defp apply_result(request, association, header, encoded_header, protected_data, mac) do
    %ApplyResult{
      payload: encoded_header <> protected_data <> mac,
      security_header: encoded_header,
      data: protected_data,
      security_trailer: mac,
      spi: association.spi,
      initialization_vector: header.initialization_vector,
      sequence_number: header.sequence_number,
      pad_length: header.pad_length,
      meta: request.meta
    }
  end

  defp validate_apply_request(request) do
    with :ok <- Channel.validate(request.channel),
         :ok <- validate_atom(request.service, :service),
         :ok <- validate_binary(request.frame_prefix, :frame_prefix),
         :ok <- validate_binary(request.data, :data) do
      validate_map(request.meta, :meta)
    end
  end

  defp fetch_outbound_association(channel, state) do
    case Map.fetch(state.outbound_by_channel, Channel.key(channel)) do
      {:ok, key} -> {:ok, key, Map.fetch!(state.associations, key)}
      :error -> {:error, {:no_active_security_association, Channel.key(channel)}}
    end
  end

  defp index_associations([]), do: {:error, :empty_security_association_plan}

  defp index_associations(associations) do
    Enum.reduce_while(associations, {:ok, %{}}, fn association, {:ok, indexed} ->
      with %SecurityAssociation{} <- association,
           :ok <- SecurityAssociation.validate(association),
           key = {SecurityAssociation.physical_channel(association), association.spi},
           false <- Map.has_key?(indexed, key) do
        {:cont, {:ok, Map.put(indexed, key, association)}}
      else
        true -> {:halt, {:error, {:duplicate_security_parameter_index, association.spi}}}
        {:error, reason} -> {:halt, {:error, reason}}
        value -> {:halt, {:error, {:invalid_security_association, value}}}
      end
    end)
  end

  defp index_outbound_channels(associations) do
    associations
    |> Enum.filter(fn {_key, association} -> association.active? end)
    |> Enum.reduce_while({:ok, %{}}, &index_outbound_association/2)
  end

  defp index_outbound_association({association_key, association}, {:ok, indexed}) do
    case add_outbound_channels(association.channels, association_key, indexed) do
      {:ok, next_indexed} -> {:cont, {:ok, next_indexed}}
      {:error, _reason} = error -> {:halt, error}
    end
  end

  defp add_outbound_channels(channels, association_key, indexed) do
    Enum.reduce_while(channels, {:ok, indexed}, fn channel, {:ok, acc} ->
      key = Channel.key(channel)

      if Map.has_key?(acc, key),
        do: {:halt, {:error, {:multiple_active_security_associations, key}}},
        else: {:cont, {:ok, Map.put(acc, key, association_key)}}
    end)
  end

  defp validate_crypto_provider(provider) do
    case Code.ensure_loaded(provider) do
      {:module, ^provider} -> validate_crypto_callbacks(provider)
      {:error, reason} -> {:error, {:crypto_provider_not_available, provider, reason}}
    end
  end

  defp validate_crypto_callbacks(provider) do
    missing =
      Enum.reject(@required_callbacks, fn {name, arity} ->
        function_exported?(provider, name, arity)
      end)

    if missing == [], do: :ok, else: {:error, {:missing_crypto_provider_callbacks, missing}}
  end

  defp initial_state(association) do
    %{
      sequence_number: association.sequence_number,
      initialization_vector: association.initialization_vector
    }
  end

  defp validate_iv(value, association) do
    expected = association.initialization_vector_length

    if is_binary(value) and byte_size(value) == expected,
      do: :ok,
      else: {:error, {:initialization_vector_length_mismatch, byte_size_safe(value), expected}}
  end

  defp validate_binary(value, _field) when is_binary(value), do: :ok
  defp validate_binary(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_atom(value, _field) when is_atom(value) and not is_nil(value), do: :ok
  defp validate_atom(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_map(value, _field) when is_map(value), do: :ok
  defp validate_map(value, field), do: {:error, {:invalid_field, field, value}}

  defp failure(code, reason, spi \\ nil),
    do: %Verification{status: :failure, code: code, reason: reason, spi: spi}

  defp byte_size_safe(value) when is_binary(value), do: byte_size(value)
  defp byte_size_safe(_value), do: :invalid
end
