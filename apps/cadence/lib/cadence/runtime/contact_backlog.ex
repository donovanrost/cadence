defmodule Cadence.Runtime.ContactBacklog do
  @moduledoc """
  What a realized contact's runtime hasn't stored yet (DECISIONS #71), read while it still runs
  and before it stops: per ingress journal, the entries past its durable processing cursor (the
  offset a restart resumes from), and the persistence projectors' last errors.
  """

  alias Cadence.IngressJournal.FileSystem, as: IngressJournal

  alias Cadence.Runtime.{
    Cluster,
    IngressJournalConsumer,
    IngressPersistenceProjector,
    ProcessNamespace
  }

  @type journal :: %{
          path_id: binary(),
          provider_binding_id: binary(),
          from_offset: non_neg_integer(),
          to_offset: non_neg_integer(),
          entries: non_neg_integer(),
          bytes: non_neg_integer()
        }

  @spec read(ProcessNamespace.t(), binary(), binary()) ::
          %{journals: [journal()], persistence_errors: [binary()], queued: non_neg_integer()}
  def read(%ProcessNamespace{} = namespace, mission_id, realized_contact_id) do
    projectors = projectors(namespace, mission_id, realized_contact_id)

    %{
      journals: journals(namespace, mission_id, realized_contact_id),
      persistence_errors: for(%{last_error: e} <- projectors, is_binary(e), do: e),
      queued: projectors |> Enum.map(&Map.get(&1, :queue_depth, 0)) |> Enum.sum()
    }
  end

  defp journals(namespace, mission_id, realized_contact_id) do
    namespace
    |> registered(:provider_ingress_journal, mission_id, realized_contact_id)
    |> Enum.flat_map(fn {path_id, provider_binding_id, pid} ->
      case IngressJournal.snapshot(pid) do
        {:ok, %{processing_backlog: %{bytes: bytes} = backlog}} when bytes > 0 ->
          [Map.merge(backlog, %{path_id: path_id, provider_binding_id: provider_binding_id})]

        _drained_or_gone ->
          []
      end
    end)
    |> Enum.sort_by(&{&1.path_id, &1.provider_binding_id})
  catch
    :exit, _reason -> []
  end

  # Each projector's snapshot: its last error, and the batches still queued in memory (with the
  # journal off, those are all that's left of what the contact received).
  defp projectors(namespace, mission_id, realized_contact_id) do
    namespace
    |> registered(:provider_persistence_projector, mission_id, realized_contact_id)
    |> Enum.flat_map(fn {_path_id, _provider_binding_id, pid} ->
      case IngressPersistenceProjector.snapshot(pid) do
        {:ok, snapshot} -> [snapshot]
        _gone -> []
      end
    end)
  catch
    :exit, _reason -> []
  end

  @doc """
  What the contact's journal consumers gave up at the end of their streams (a frame or packet that
  never completed, domain's partial-frame fix 11-15): `[%{path_id, provider_binding_id,
  frame_bytes, packet_octets, journal_bytes}]`, only those that gave anything up.
  """
  @spec incomplete_at_end(term(), binary(), binary()) :: [map()]
  def incomplete_at_end(namespace, mission_id, realized_contact_id) do
    namespace
    |> registered(:provider_ingress_journal_consumer, mission_id, realized_contact_id)
    |> Enum.flat_map(fn {path_id, provider_binding_id, pid} ->
      consumer_incomplete(pid, %{path_id: path_id, provider_binding_id: provider_binding_id})
    end)
  catch
    # The registry select itself (registry or :global trouble) mustn't crash the settler mid-settle.
    :exit, _reason -> []
  end

  # One consumer gone (or a remote call timing out) leaves out only its own entry (api-ops).
  defp consumer_incomplete(pid, ids) do
    case IngressJournalConsumer.snapshot(pid) do
      {:ok, %{incomplete_at_end: %{journal_bytes: bytes} = incomplete}} when bytes > 0 ->
        [Map.merge(incomplete, ids)]

      _nothing ->
        []
    end
  catch
    :exit, _reason -> []
  end

  @doc """
  The frame-SCID cross-check's tally of each of the contact's journal consumers (DECISIONS #102):
  `[%{path_id, provider_binding_id, expected_scid, frames, refused: %{scid => count}}]`, every
  path that checked any frame (refusing or not: "most" is over all of the contact's frames).
  """
  @spec scid_checks(term(), binary(), binary()) :: [map()]
  def scid_checks(namespace, mission_id, realized_contact_id) do
    namespace
    |> registered(:provider_ingress_journal_consumer, mission_id, realized_contact_id)
    |> Enum.flat_map(fn {path_id, provider_binding_id, pid} ->
      consumer_scid_check(pid, %{path_id: path_id, provider_binding_id: provider_binding_id})
    end)
  catch
    :exit, _reason -> []
  end

  defp consumer_scid_check(pid, ids) do
    case IngressJournalConsumer.snapshot(pid) do
      {:ok, %{scid_check: %{frames: frames} = check}} when frames > 0 -> [Map.merge(check, ids)]
      _nothing -> []
    end
  catch
    :exit, _reason -> []
  end

  defp registered(namespace, kind, mission_id, realized_contact_id) do
    Cluster.select(namespace, [
      {{{kind, mission_id, realized_contact_id, :"$1", :"$2"}, :"$3", :_}, [],
       [{{:"$1", :"$2", :"$3"}}]}
    ])
  end
end
