defmodule Cadence.Protocol.RecordArchive.FileSystem.PoisonIsolation do
  @moduledoc """
  Persists a mission's buffered archive entries, isolating entries that can never be indexed
  (DECISIONS #88; api-ops' writer review A-F).

  Classification errs toward TRANSIENT. Only these isolate entries:

  - `{:protocol_archive_record_identity_conflict, ids}` names its entries exactly;
  - a Postgres data or integrity error (SQLSTATE class 22 or 23) is bisected with rolled-back
    probes, and isolates only while exactly ONE half fails at each step. If both halves fail,
    or neither does, it's environmental (a schema problem, permissions) and stays transient, so
    a bad deploy never quarantines a mission's archive.

  Isolated entries go to `quarantine` (a callback; when it refuses, e.g. the cap, the whole flush
  stays transient). The failed segment object, never indexed because its transaction rolled
  back, is removed, and the rest is written under a FRESH segment id: the writer's retained id
  must not be rewritten with fewer entries (DurableFile.write_new verifies identical content).
  """

  alias Cadence.Protocol.RecordArchive.FileSystem

  @max_rounds 3

  @type result :: %{
          size_bytes: non_neg_integer(),
          indexed: non_neg_integer(),
          quarantined: [map()]
        }

  @spec persist(binary(), [map()], keyword(), ([map()] -> :ok | {:error, term()})) ::
          {:ok, result()} | {:error, term()}
  def persist(segment_id, entries, opts, quarantine) when is_function(quarantine, 1),
    do: persist(segment_id, entries, opts, quarantine, %{rounds: 0, quarantined: []})

  defp persist(_segment_id, [], _opts, _quarantine, acc),
    do: {:ok, %{size_bytes: 0, indexed: 0, quarantined: acc.quarantined}}

  defp persist(segment_id, entries, opts, quarantine, acc) do
    with {:ok, object_key, size_bytes} <-
           FileSystem.store_segment_object(segment_id, entries, opts) do
      case attempt(segment_id, entries, object_key, opts) do
        :ok ->
          {:ok, %{size_bytes: size_bytes, indexed: length(entries), quarantined: acc.quarantined}}

        {:error, reason} ->
          isolate(reason, entries, object_key, opts, quarantine, acc)
      end
    end
  end

  defp attempt(segment_id, entries, object_key, opts) do
    FileSystem.persist_segment(segment_id, entries, Keyword.put(opts, :object_key, object_key))
  rescue
    error in Postgrex.Error -> {:error, {:archive_data_error, error}}
  end

  defp isolate(reason, entries, object_key, opts, quarantine, acc) do
    case poison(reason, entries, opts) do
      {:isolated, poisoned, rest} when acc.rounds < @max_rounds ->
        with :ok <- quarantine.(poisoned) do
          _ = remove_object(object_key, opts)

          persist(FileSystem.new_segment_id(), rest, opts, quarantine, %{
            rounds: acc.rounds + 1,
            quarantined: acc.quarantined ++ poisoned
          })
        end

      _transient ->
        {:error, transient(reason)}
    end
  end

  # The isolated entries with their error, and the rest; or :transient.
  defp poison({:protocol_archive_record_identity_conflict, ids}, entries, opts) do
    named = MapSet.new(ids)

    {poisoned, rest} =
      Enum.split_with(entries, &MapSet.member?(named, FileSystem.entry_index_record_id(&1, opts)))

    case poisoned do
      [] -> :transient
      _ -> {:isolated, Enum.map(poisoned, &quarantined(&1, "identity_conflict", nil)), rest}
    end
  end

  defp poison({:archive_data_error, %Postgrex.Error{} = error}, entries, opts) do
    if data_error?(error) do
      case bisect(entries, opts) do
        {:isolated, [entry]} ->
          rest = Enum.reject(entries, &(&1 === entry))
          {:isolated, [quarantined(entry, "data_rejected", Exception.message(error))], rest}

        :not_isolated ->
          :transient
      end
    else
      :transient
    end
  end

  defp poison(_reason, _entries, _opts), do: :transient

  # SQLSTATE class 22 (data exception) or 23 (integrity violation): about the row's data.
  defp data_error?(%Postgrex.Error{postgres: %{pg_code: <<class::binary-size(2), _::binary>>}}),
    do: class in ["22", "23"]

  defp data_error?(_error), do: false

  # Exactly one half fails at every step, down to a single entry; anything else isn't isolated.
  defp bisect([entry], _opts), do: {:isolated, [entry]}

  defp bisect(entries, opts) do
    {left, right} = Enum.split(entries, div(length(entries), 2))

    case {probe(left, opts), probe(right, opts)} do
      {:fail, :ok} -> bisect(left, opts)
      {:ok, :fail} -> bisect(right, opts)
      _both_or_neither -> :not_isolated
    end
  end

  # Indexes `entries` in a transaction that is always rolled back: :ok, :fail (a data error),
  # or :error (anything else, which stops the bisect).
  defp probe(entries, opts) do
    repo = Keyword.get(opts, :repo, Cadence.Repo)

    repo.transaction(fn ->
      result =
        FileSystem.persist_segment(
          "probe",
          entries,
          opts |> Keyword.delete(:base_path) |> Keyword.put(:object_key, "probe")
        )

      repo.rollback({:probe, result})
    end)
    |> case do
      {:error, {:probe, :ok}} -> :ok
      {:error, {:probe, _other}} -> :error
    end
  rescue
    error in Postgrex.Error -> if data_error?(error), do: :fail, else: :error
  end

  defp quarantined(entry, code, error), do: %{entry: entry, error_code: code, error: error}

  defp remove_object(object_key, opts) do
    case Keyword.fetch(opts, :base_path) do
      {:ok, base_path} -> File.rm(Path.join(base_path, object_key))
      :error -> :ok
    end
  end

  defp transient({:archive_data_error, %Postgrex.Error{} = error}),
    do: {:archive_database_error, Exception.message(error)}

  defp transient(reason), do: reason
end
