defmodule Cadence.Contacts.ContactStartFailure do
  @moduledoc """
  A realized contact whose runtime failed to start (ux U45). The failure is kept on the
  contact's metadata as `start_failure`, so the scheduler's reconcile retries it while its
  window is open and the `contact_start` attention item shows it, until it starts or, once the
  window has ended, an operator marks the missed pass as seen.

  Tonight's case (11-14, EARENDIL-001): two passes on one listen-mode provider profile overlapped,
  so the second couldn't open the station listener (`eaddrinuse`) until the first one ended.

  `start_failure`: `reason` (one of `reasons/0`), `failure_message` (the raw error, cut to 300
  characters), `provider_binding_id` (the listener's, for `listener_in_use` and
  `listen_endpoint_claimed`), `attempts`, `first_failed_at`, `last_attempt_at`, and, once it has
  started, `started_at`. For `listen_endpoint_claimed` (another mission listens on the pass's
  port, ux U81) also `listen_port`, `transport_id` and `transport_name`; for `transport_archived`
  (its path is pinned to the provider profile of a transport since archived, ux U45) also
  `transport_id` and `transport_name`, that transport's.
  """

  alias Cadence.Contacts.{ContactStore, RealizedContact, ScheduledContact}
  alias Cadence.Platform.ScopedReadUpdates

  @reasons ~w(listener_in_use listener_unavailable connect_failed ingress_pipeline_failed
              uplink_session_failed no_runtime_spec listen_endpoint_claimed transport_archived
              unknown)

  # Matched by name: the runtime's children are the data plane's, not this context's to depend on.
  @ingress_children ~w(IngressJournal.FileSystem Runtime.IngressJournalConsumer
                       Runtime.IngressArchiveConsumer Runtime.IngressPersistenceProjector
                       Runtime.ProviderIngressExecutor)
  @transport_child "Runtime.TransportRuntime"

  @message_chars 300

  @doc "The reason keys (ux U45 words each one)."
  @spec reasons() :: [binary()]
  def reasons, do: @reasons

  @doc """
  The metadata patch recording a failed start attempt at `at`: on the realized contact, or on
  the scheduled contact when its realization failed (`RealizationFailure`).
  """
  @spec failed(RealizedContact.t() | ScheduledContact.t(), term(), DateTime.t()) :: map()
  def failed(%{metadata: _metadata} = contact, error, %DateTime{} = at) do
    previous = open_failure(contact) || %{}
    {reason, provider_binding_id} = classify(error)
    at = DateTime.to_iso8601(at)

    %{
      "start_failure" =>
        %{
          "reason" => reason,
          "provider_binding_id" => provider_binding_id,
          "failure_message" => message(error),
          "attempts" => Map.get(previous, "attempts", 0) + 1,
          "first_failed_at" => Map.get(previous, "first_failed_at", at),
          "last_attempt_at" => at
        }
        |> Map.merge(claim_details(error))
        |> Map.merge(runtime_spec_detail(reason, error))
    }
  end

  # U91: no_runtime_spec has two causes an operator must tell apart. No configuration activated
  # is the mission's to fix (Open Changes); one that fails its integrity check (a spec mismatch)
  # is Cadence's (Open pass, never Changes). The failed field stays in failure_message.
  defp runtime_spec_detail("no_runtime_spec", error) do
    case spec_cause(error) do
      nil -> %{}
      detail -> %{"reason_detail" => detail}
    end
  end

  defp runtime_spec_detail(_reason, _error), do: %{}

  defp spec_cause(:no_active_binding_set), do: "no_configuration"
  defp spec_cause({:mission_runtime_spec_mismatch, _field}), do: "configuration_unverifiable"

  defp spec_cause(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.find_value(&spec_cause/1)

  defp spec_cause(list) when is_list(list), do: Enum.find_value(list, &spec_cause/1)
  defp spec_cause(_other), do: nil

  # `listen_endpoint_claimed` (ListenClaims, ux U81): the port another mission listens on and the
  # transport whose port it is, so the item can say which port to change.
  defp claim_details({:listen_endpoint_claimed, %{port: port} = claim}),
    do: %{
      "listen_port" => port,
      "transport_id" => Map.get(claim, :transport_id),
      "transport_name" => Map.get(claim, :transport_name)
    }

  defp claim_details(error) do
    case find_archived(error) do
      %{} = transport ->
        %{"transport_id" => transport.transport_id, "transport_name" => transport.transport_name}

      nil ->
        %{}
    end
  end

  # ArchivedProfile's refusal, wherever the runtime nests it.
  defp find_archived({:contact_provider_profile_archived, %{} = transport}), do: transport

  defp find_archived(term) when is_tuple(term),
    do: term |> Tuple.to_list() |> Enum.find_value(&find_archived/1)

  defp find_archived(term) when is_list(term), do: Enum.find_value(term, &find_archived/1)
  defp find_archived(_term), do: nil

  @doc "Records a failed start attempt on the contact and tells the Now queue."
  @spec record(RealizedContact.t(), term(), DateTime.t()) ::
          {:ok, RealizedContact.t()} | {:error, term()}
  def record(%RealizedContact{} = contact, error, %DateTime{} = at) do
    with {:ok, %RealizedContact{} = updated} <-
           ContactStore.update_realized_lifecycle(
             contact,
             contact.lifecycle_state,
             failed(contact, error, at)
           ) do
      announce(updated)
      {:ok, updated}
    end
  end

  @doc "Tells the Now queue a contact that had failed to start has started."
  @spec announce_started(RealizedContact.t()) :: :ok
  def announce_started(%RealizedContact{} = contact) do
    if open_failure(contact), do: announce(contact)
    :ok
  end

  defp announce(%RealizedContact{organization_id: org, mission_id: mission})
       when is_binary(org),
       do: ScopedReadUpdates.publish(:attention_changed, org, mission)

  defp announce(%RealizedContact{}), do: :ok

  @doc "The metadata patch for a contact that started after failing; `%{}` if it never failed."
  @spec started(RealizedContact.t(), DateTime.t()) :: map()
  def started(%RealizedContact{} = contact, %DateTime{} = at) do
    case open_failure(contact) do
      nil -> %{}
      failure -> %{"start_failure" => Map.put(failure, "started_at", DateTime.to_iso8601(at))}
    end
  end

  @doc """
  The contact's failure while it hasn't started (or, on a scheduled contact, been realized) since,
  else nil.
  """
  @spec open_failure(RealizedContact.t() | ScheduledContact.t()) :: map() | nil
  def open_failure(%{metadata: %{"start_failure" => %{} = failure}})
      when not is_map_key(failure, "started_at") and not is_map_key(failure, "realized_at"),
      do: failure

  def open_failure(%{}), do: nil

  @doc """
  `{reason, provider_binding_id}` for a start error. The runtime nests the cause in
  `{:failed_to_start_child, module, cause}` (and `{:shutdown, …}`), so the error is searched.
  """
  @spec classify(term()) :: {binary(), binary() | nil}
  def classify(error), do: find(error) || {"unknown", nil}

  defp find({:tcp_provider_listen_failed, binding_id, :eaddrinuse}),
    do: {"listener_in_use", binding_id}

  defp find({:tcp_provider_listen_failed, binding_id, _reason}),
    do: {"listener_unavailable", binding_id}

  defp find({:tcp_provider_connect_failed, binding_id, _reason}),
    do: {"connect_failed", binding_id}

  defp find({:listen_endpoint_claimed, %{} = claim}),
    do: {"listen_endpoint_claimed", Map.get(claim, :provider_binding_id)}

  defp find({:contact_provider_profile_archived, %{}}), do: {"transport_archived", nil}

  defp find(:no_active_binding_set), do: {"no_runtime_spec", nil}
  defp find({:mission_runtime_spec_mismatch, _field}), do: {"no_runtime_spec", nil}

  defp find({:invalid_transport_extension_descriptor, _kind}),
    do: {"uplink_session_failed", nil}

  defp find({:failed_to_start_child, module, cause}) do
    find(cause) ||
      cond do
        child?(module, [@transport_child]) -> {"uplink_session_failed", nil}
        child?(module, @ingress_children) -> {"ingress_pipeline_failed", nil}
        true -> nil
      end
  end

  defp find(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> Enum.find_value(&find/1)
  defp find(list) when is_list(list), do: Enum.find_value(list, &find/1)
  defp find(_other), do: nil

  defp child?(module, names) when is_atom(module) do
    name = inspect(module)
    Enum.any?(names, &(name == "Cadence." <> &1))
  end

  defp child?(_module, _names), do: false

  defp message(error) do
    error |> inspect(limit: 20, printable_limit: 200) |> String.slice(0, @message_chars)
  end
end
