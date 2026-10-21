defmodule Cadence.Telemetry.Storage.QuestDB.ObservationWriter do
  @moduledoc """
  Writes observation envelopes into Cadence-managed QuestDB storage.

  The writer assumes the QuestDB schema has already been applied with
  `mix cadence.questdb.migrate`.
  """

  alias Cadence.Telemetry.Storage.ObservationEnvelope
  alias Cadence.Telemetry.Storage.QuestDB.{ObservationLine, ObservationRow, RestClient}

  # /exec accepts SQL in the URL. Leave room below the URL query-string
  # limit, including percent encoding and the other request parameters.
  @max_encoded_query_bytes 24_000

  @spec persist_envelopes([ObservationEnvelope.t()], keyword()) :: :ok | {:error, term()}
  def persist_envelopes(envelopes, opts \\ []) when is_list(envelopes) and is_list(opts) do
    case envelopes do
      [] ->
        :ok

      [_ | _] ->
        case Keyword.get(opts, :write_protocol, :ilp) do
          :ilp -> persist_lines(envelopes, opts)
          :sql -> persist_envelopes_with_client(envelopes, opts)
        end
    end
  end

  defp persist_lines(envelopes, opts) do
    write_fun = Keyword.get(opts, :write_fun, &RestClient.write/2)

    envelopes
    |> deduplicate_envelopes()
    |> Enum.map(&ObservationLine.encode/1)
    |> line_batches()
    |> Enum.reduce_while(:ok, fn lines, :ok ->
      case write_fun.(Enum.join(lines), opts) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp line_batches(lines) do
    Enum.chunk_while(
      lines,
      {[], 0},
      fn line, {batch, size} ->
        if batch != [] and size + byte_size(line) > 1_000_000 do
          {:cont, Enum.reverse(batch), {[line], byte_size(line)}}
        else
          {:cont, {[line | batch], size + byte_size(line)}}
        end
      end,
      fn
        {[], _size} -> {:cont, []}
        {batch, _size} -> {:cont, Enum.reverse(batch), []}
      end
    )
  end

  @spec persist_envelopes_with_client([ObservationEnvelope.t()], keyword()) ::
          :ok | {:error, term()}
  def persist_envelopes_with_client(envelopes, opts) when is_list(envelopes) and is_list(opts) do
    envelopes
    |> deduplicate_envelopes()
    |> insert_batches()
    |> Enum.reduce_while(:ok, fn batch, :ok ->
      case persist_batch(batch, opts) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp deduplicate_envelopes(envelopes) do
    envelopes
    |> Enum.reverse()
    |> Enum.uniq_by(&upsert_key/1)
    |> Enum.reverse()
  end

  defp upsert_key(%ObservationEnvelope{} = envelope) do
    {ObservationRow.observed_at(envelope), envelope.idempotency_key}
  end

  defp insert_batches(envelopes) do
    Enum.chunk_while(
      envelopes,
      {[], 0},
      fn envelope, {batch, size} ->
        # Counting a full INSERT per row is a conservative upper bound for
        # the combined statement, whose column list is emitted only once.
        row_size = envelope |> ObservationRow.insert_sql() |> URI.encode_www_form() |> byte_size()

        if batch != [] and size + row_size > @max_encoded_query_bytes do
          {:cont, Enum.reverse(batch), {[envelope], row_size}}
        else
          {:cont, {[envelope | batch], size + row_size}}
        end
      end,
      fn
        {[], _size} -> {:cont, []}
        {batch, _size} -> {:cont, Enum.reverse(batch), []}
      end
    )
  end

  defp persist_batch(envelopes, opts) do
    exec_fun = Keyword.get(opts, :exec_fun, &RestClient.exec/2)

    case exec_fun.(ObservationRow.insert_sql(envelopes), opts) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
