defmodule Cadence.Runtime.ContactBacklog do
  @moduledoc """
  What a realized contact's runtime hasn't stored yet (DECISIONS #71), read while it still runs
  and before it stops: per ingress journal, the entries past its durable processing cursor (the
  offset a restart resumes from), and the persistence projectors' last errors.
  """

  alias Cadence.IngressJournal.FileSystem, as: IngressJournal
  alias Cadence.Runtime.{Cluster, IngressPersistenceProjector, ProcessNamespace}

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

  defp registered(namespace, kind, mission_id, realized_contact_id) do
    Cluster.select(namespace, [
      {{{kind, mission_id, realized_contact_id, :"$1", :"$2"}, :"$3", :_}, [],
       [{{:"$1", :"$2", :"$3"}}]}
    ])
  end
end
