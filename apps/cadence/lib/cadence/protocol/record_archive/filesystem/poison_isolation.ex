defmodule Cadence.Protocol.RecordArchive.FileSystem.PoisonIsolation do
  @moduledoc """
  Persists a mission's buffered archive entries, isolating entries that can never be indexed
  (DECISIONS #88; api-ops' writer review A-F).

  Classification errs toward TRANSIENT. Only these isolate entries:

  - `{:protocol_archive_record_identity_conflict, ids}` names its entries exactly;
  - `{:protocol_archive_invalid_entries, ids}` names entries whose bytes cannot be read (a packet
    whose stored data is not valid base64), quarantined as `data_rejected`;
  - a Postgres data or integrity error (SQLSTATE class 22 or 23) is bisected with rolled-back
    probes (bounded) to find every entry that fails on its own. If EVERY entry fails, it's
    environmental (a schema problem, permissions) and stays transient, so a bad deploy never
    quarantines a mission's archive; a strict subset is quarantined in one round.

  Isolated entries go to `quarantine` (a callback; when it refuses, e.g. the cap, the whole flush
  stays transient). The failed segment object, never indexed because its transaction rolled
  back, is removed, and the rest is written under a FRESH segment id: the writer's retained id
  must not be rewritten with fewer entries (DurableFile.write_new verifies identical content).
  """

  alias Cadence.Protocol.RecordArchive.FileSystem

  @max_rounds 8
  @max_probes 256

  @type result :: %{
          size_bytes: non_neg_integer(),
          indexed: non_neg_integer(),
          quarantined: [map()]
        }

  @doc """
  `{:ok, result}`, or `{:error, reason}` with nothing isolated (the writer keeps its buffer and
  segment id as they were), or `{:error, reason, quarantined}` when a later round ended transient
  after earlier ones quarantined entries: the writer drops those from its buffer and takes a
  fresh segment id, so every retry makes progress (api-ops, #88 review).
  """
  @spec persist(binary(), [map()], keyword(), ([map()] -> :ok | {:error, term()})) ::
          {:ok, result()} | {:error, term()} | {:error, term(), [map()]}
  def persist(segment_id, entries, opts, quarantine) when is_function(quarantine, 1),
    do: persist(segment_id, entries, opts, quarantine, %{rounds: 0, quarantined: []})

  defp persist(_segment_id, [], _opts, _quarantine, acc),
    do: {:ok, %{size_bytes: 0, indexed: 0, quarantined: acc.quarantined}}

  defp persist(segment_id, entries, opts, quarantine, acc) do
    case FileSystem.store_segment_object(segment_id, entries, opts) do
      {:ok, object_key, size_bytes} ->
        case attempt(segment_id, entries, object_key, opts) do
          :ok ->
            {:ok,
             %{size_bytes: size_bytes, indexed: length(entries), quarantined: acc.quarantined}}

          {:error, reason} ->
            isolate(reason, entries, object_key, opts, quarantine, acc)
        end

      {:error, reason} ->
        transient_end(reason, nil, opts, acc)
    end
  end

  defp attempt(segment_id, entries, object_key, opts) do
    FileSystem.persist_segment(segment_id, entries, Keyword.put(opts, :object_key, object_key))
  rescue
    error in Postgrex.Error -> {:error, {:archive_data_error, error}}
  end

  defp isolate(reason, entries, object_key, opts, quarantine, acc) do
    with {:isolated, poisoned, rest} when acc.rounds < @max_rounds <-
           poison(reason, entries, opts),
         :ok <- quarantine.(poisoned) do
      _ = remove_object(object_key, opts)

      persist(FileSystem.new_segment_id(), rest, opts, quarantine, %{
        rounds: acc.rounds + 1,
        quarantined: acc.quarantined ++ poisoned
      })
    else
      {:error, refused} -> transient_end(refused, object_key, opts, acc)
      _not_isolated -> transient_end(transient(reason), object_key, opts, acc)
    end
  end

  # Nothing isolated yet: the writer retries its buffer under its own segment id, so that object
  # stays. After a partial isolation the current round's object was never indexed and its id is
  # fresh: remove it (no orphan), and hand back what was quarantined.
  defp transient_end(reason, _object_key, _opts, %{quarantined: []}), do: {:error, reason}

  defp transient_end(reason, object_key, opts, acc) do
    _ = object_key && remove_object(object_key, opts)
    {:error, reason, acc.quarantined}
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

  defp poison({:protocol_archive_invalid_entries, ids}, entries, opts) do
    named = MapSet.new(ids)

    {poisoned, rest} =
      Enum.split_with(entries, &MapSet.member?(named, FileSystem.entry_index_record_id(&1, opts)))

    case poisoned do
      [] ->
        :transient

      _ ->
        message = "packet data is not valid base64"
        {:isolated, Enum.map(poisoned, &quarantined(&1, "data_rejected", message)), rest}
    end
  end

  defp poison({:archive_data_error, %Postgrex.Error{} = error}, entries, opts) do
    with true <- data_error?(error),
         {:ok, failing, _budget} <- failing(entries, opts, @max_probes),
         true <- failing != [] and length(failing) < length(entries) do
      failed = MapSet.new(failing)
      {poisoned, rest} = Enum.split_with(entries, &MapSet.member?(failed, &1))
      message = Exception.message(error)
      {:isolated, Enum.map(poisoned, &quarantined(&1, "data_rejected", message)), rest}
    else
      # Every entry fails (environmental: a schema problem, permissions), the probes ran out, or
      # a probe hit something that isn't a data error: transient (api-ops B).
      _not_isolated -> :transient
    end
  end

  defp poison(_reason, _entries, _opts), do: :transient

  # SQLSTATE class 22 (data exception) or 23 (integrity violation): about the row's data.
  defp data_error?(%Postgrex.Error{postgres: %{pg_code: <<class::binary-size(2), _::binary>>}}),
    do: class in ["22", "23"]

  defp data_error?(_error), do: false

  # Every entry that fails on its own, by bisecting halves that fail (rolled-back probes), within
  # a probe budget. `entries` is known to fail as a whole.
  defp failing([entry], _opts, budget), do: {:ok, [entry], budget}

  defp failing(entries, opts, budget) do
    {left, right} = Enum.split(entries, div(length(entries), 2))

    with {:ok, left_failing, budget} <- failing_half(left, opts, budget),
         {:ok, right_failing, budget} <- failing_half(right, opts, budget) do
      {:ok, left_failing ++ right_failing, budget}
    end
  end

  defp failing_half(_entries, _opts, 0), do: :exhausted

  defp failing_half(entries, opts, budget) do
    case probe(entries, opts) do
      :ok -> {:ok, [], budget - 1}
      :fail -> failing(entries, opts, budget - 1)
      :error -> :error
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
      # No data error in this half; its identity conflicts are isolated in a later round.
      {:error, {:probe, {:error, {:protocol_archive_record_identity_conflict, _ids}}}} -> :ok
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
