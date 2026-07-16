defmodule Cadence.GroundNetworks.ProviderEventPoller do
  @moduledoc "Bounded polling lane over active organization Provider Accounts."

  use GenServer

  alias Cadence.Contacts.ProviderClients.Registry

  alias Cadence.GroundNetworks.{
    CredentialResolver,
    ProviderAccounts,
    ProviderAccountVersion,
    ProviderAudit,
    ProviderAuditEntry,
    ProviderContext,
    ProviderEventCursors,
    ProviderEventInbox,
    Validation
  }

  alias Cadence.Persistence.JsonDocument

  @default_poll_interval_ms 5_000
  @default_max_concurrency 4
  @default_lease_ms 30_000

  def start_link(opts) when is_list(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec poll_now(GenServer.server()) :: {:ok, map()}
  def poll_now(server \\ __MODULE__), do: GenServer.call(server, :poll_now, :infinity)

  @spec poll_once(keyword()) :: {:ok, map()}
  def poll_once(opts \\ []) when is_list(opts) do
    accounts = Keyword.get_lazy(opts, :accounts, &ProviderAccounts.list_polling_accounts/0)

    results =
      accounts
      |> Task.async_stream(
        &poll_account(&1, opts),
        max_concurrency: Keyword.get(opts, :max_concurrency, @default_max_concurrency),
        ordered: false,
        timeout: :infinity
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> {:error, {:provider_event_poll_task_exit, reason}}
      end)

    {:ok, summarize(results)}
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :poll_interval_ms, @default_poll_interval_ms)
    schedule_poll(interval)
    {:ok, %{interval: interval, poll_opts: Keyword.delete(opts, :name)}}
  end

  @impl true
  def handle_call(:poll_now, _from, state) do
    result = poll_once(state.poll_opts)
    {:reply, result, state}
  end

  @impl true
  def handle_info(:poll, state) do
    _result = poll_once(state.poll_opts)
    schedule_poll(state.interval)
    {:noreply, state}
  end

  defp poll_account({_account, %ProviderAccountVersion{} = version}, opts) do
    lease_owner = lease_owner(version, opts)
    started_at = System.monotonic_time()

    result =
      with {:ok, cursor} <- ProviderEventCursors.ensure(version, opts),
           {:ok, claimed} <-
             ProviderEventCursors.claim(cursor.provider_event_cursor_id, lease_owner,
               now: now(opts),
               lease_ms: Keyword.get(opts, :lease_ms, @default_lease_ms)
             ),
           {:ok, context} <- ProviderContext.from_account_version(version),
           {:ok, client} <- resolve_client(context, opts),
           {:ok, resolver} <- resolve_page_credential(version, opts),
           {:ok, page} <- client.events(context, claimed.cursor, call_opts(opts, resolver)),
           {:ok, deliveries, next_cursor} <- normalize_page(page),
           {:ok, summary} <-
             ProviderEventInbox.ingest_page(
               claimed,
               deliveries,
               next_cursor,
               lease_owner,
               Keyword.put(opts, :now, now(opts))
             ) do
        {:ok, version, summary}
      else
        {:error, :lease_unavailable} -> {:skipped, version, :lease_unavailable}
        {:error, reason} -> fail_account(version, lease_owner, reason, opts)
      end

    emit_poll_telemetry(result, started_at)
    result
  end

  defp resolve_page_credential(version, opts) do
    resolver = CredentialResolver.resolver(opts)

    case resolver.(version.credential_ref) do
      {:ok, material} when is_binary(material) and material != "" ->
        {:ok, fn reference -> cached_credential(reference, version.credential_ref, material) end}

      {:error, reason} ->
        {:error, reason}

      _other ->
        {:error, :invalid_provider_credential_resolution}
    end
  end

  defp cached_credential(reference, reference, material), do: {:ok, material}

  defp cached_credential(_reference, _expected, _material),
    do: {:error, :credential_scope_mismatch}

  defp resolve_client(context, opts) do
    case Keyword.fetch(opts, :client) do
      {:ok, client} -> {:ok, client}
      :error -> Registry.fetch(context)
    end
  end

  defp normalize_page(%{data: deliveries, next_cursor: next_cursor}) when is_list(deliveries),
    do: {:ok, deliveries, next_cursor}

  defp normalize_page(_page), do: {:error, :malformed_provider_event_page}

  defp fail_account(version, lease_owner, reason, opts) do
    with {:ok, cursor} <- ProviderEventCursors.ensure(version, opts) do
      _result = ProviderEventCursors.record_failure(cursor, lease_owner, reason, now: now(opts))
      _audit = ProviderAudit.append(failure_audit(version, reason, opts))
    end

    {:error, version, reason}
  end

  defp failure_audit(version, reason, opts) do
    ProviderAuditEntry.new(%{
      organization_id: version.organization_id,
      provider_account_id: version.provider_account_id,
      action: "provider_event.poll_failed",
      outcome: "failed",
      recorded_at: now(opts),
      credential_ref: version.credential_ref,
      source_document: %{
        "kind" => "poller",
        "environment_ref" => version.environment_ref
      },
      actor_document: %{"kind" => "system", "id" => "provider_event_poller"},
      current_document: %{"reason" => sanitize_reason(reason)}
    })
  end

  defp summarize(results) do
    Enum.reduce(
      results,
      %{accounts: length(results), polled: 0, skipped: 0, errors: 0, events: 0, results: results},
      fn
        {:ok, _version, summary}, acc ->
          %{acc | polled: acc.polled + 1, events: acc.events + length(summary.entries)}

        {:skipped, _version, _reason}, acc ->
          %{acc | skipped: acc.skipped + 1}

        {:error, _version, _reason}, acc ->
          %{acc | errors: acc.errors + 1}

        {:error, _reason}, acc ->
          %{acc | errors: acc.errors + 1}
      end
    )
  end

  defp call_opts(opts, resolver) do
    opts
    |> Keyword.drop([
      :accounts,
      :channel_ref,
      :client,
      :lease_ms,
      :lease_owner,
      :max_concurrency,
      :name,
      :now,
      :poll_interval_ms,
      :stream_ref
    ])
    |> Keyword.put(:credential_resolver, resolver)
  end

  defp lease_owner(version, opts) do
    Keyword.get_lazy(opts, :lease_owner, fn ->
      "provider-event-poller:#{version.provider_account_id}:#{System.unique_integer([:positive])}"
    end)
  end

  defp emit_poll_telemetry(result, started_at) do
    duration = System.monotonic_time() - started_at

    :telemetry.execute(
      [:cadence, :provider_event, :poll],
      %{duration: duration},
      %{outcome: telemetry_outcome(result)}
    )
  end

  defp telemetry_outcome({:ok, _version, _summary}), do: :ok
  defp telemetry_outcome({:skipped, _version, _reason}), do: :skipped
  defp telemetry_outcome(_result), do: :error

  defp sanitize_reason(reason) do
    case JsonDocument.encode(reason) do
      document when is_map(document) -> Validation.sanitize(document)
      value -> value
    end
  end

  defp schedule_poll(interval), do: Process.send_after(self(), :poll, interval)

  defp now(opts),
    do: opts |> Keyword.get(:now, DateTime.utc_now()) |> DateTime.truncate(:microsecond)
end
