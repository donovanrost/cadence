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
          %{journals: [journal()], persistence_errors: [binary()]}
  def read(%ProcessNamespace{} = namespace, mission_id, realized_contact_id) do
    %{
      journals: journals(namespace, mission_id, realized_contact_id),
      persistence_errors: persistence_errors(namespace, mission_id, realized_contact_id)
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

  defp persistence_errors(namespace, mission_id, realized_contact_id) do
    namespace
    |> registered(:provider_persistence_projector, mission_id, realized_contact_id)
    |> Enum.flat_map(fn {_path_id, _provider_binding_id, pid} ->
      case IngressPersistenceProjector.snapshot(pid) do
        {:ok, %{last_error: error}} when is_binary(error) -> [error]
        _ok_or_gone -> []
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
