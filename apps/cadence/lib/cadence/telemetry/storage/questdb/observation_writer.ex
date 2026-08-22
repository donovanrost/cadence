defmodule Cadence.Telemetry.Storage.QuestDB.ObservationWriter do
  @moduledoc """
  Writes observation envelopes into Cadence-managed QuestDB storage.

  The writer assumes the QuestDB schema has already been applied with
  `mix cadence.questdb.migrate`.
  """

  alias Cadence.Telemetry.Storage.ObservationEnvelope
  alias Cadence.Telemetry.Storage.QuestDB.{ObservationRow, RestClient}

  @spec persist_envelopes([ObservationEnvelope.t()], keyword()) :: :ok | {:error, term()}
  def persist_envelopes(envelopes, opts \\ []) when is_list(envelopes) and is_list(opts) do
    case envelopes do
      [] ->
        :ok

      [_ | _] ->
        persist_envelopes_with_client(envelopes, opts)
    end
  end

  @spec persist_envelopes_with_client([ObservationEnvelope.t()], keyword()) ::
          :ok | {:error, term()}
  def persist_envelopes_with_client(envelopes, opts) when is_list(envelopes) and is_list(opts) do
    envelopes
    |> deduplicate_envelopes()
    |> Enum.reduce_while(:ok, fn envelope, :ok ->
      case persist_envelope(envelope, opts) do
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

  defp persist_envelope(%ObservationEnvelope{} = envelope, opts) do
    exec_fun = Keyword.get(opts, :exec_fun, &RestClient.exec/2)

    case exec_fun.(ObservationRow.insert_sql(envelope), opts) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
