defmodule CadenceWeb.ProviderAccountShowLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.GroundNetworks.{
    ProviderAccountGrants,
    ProviderAccounts,
    ProviderAudit,
    ProviderCredentials,
    ProviderEventCursors,
    ProviderEventInbox
  }

  @impl true
  def mount(%{"provider_account_id" => provider_account_id}, _session, socket) do
    socket =
      socket
      |> stream_configure(:account_grants,
        dom_id: &"account-grant-#{&1.provider_account_grant_id}"
      )
      |> stream_configure(:account_audit, dom_id: &"account-audit-#{&1.provider_audit_entry_id}")

    case load_account(socket, provider_account_id) do
      {:ok, socket} ->
        {:ok, socket}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Provider Account not found.")
         |> push_navigate(to: ~p"/provider-accounts")}
    end
  end

  @impl true
  def handle_event("validate-account", _params, %{assigns: %{account_action: nil}} = socket) do
    scope = socket.assigns.current_scope
    account = socket.assigns.provider_account
    opts = provider_account_live_opts()

    {:noreply,
     socket
     |> assign(:account_action, :validate)
     |> start_async(:validate_account, fn ->
       ProviderAccounts.validate(scope, account.provider_account_id, opts)
     end)}
  end

  def handle_event("validate-account", _params, socket), do: {:noreply, socket}

  def handle_event("rotate-credential", _params, %{assigns: %{account_action: nil}} = socket) do
    %{current_scope: scope, provider_account: account, credential: credential} = socket.assigns
    opts = provider_account_live_opts()

    {:noreply,
     socket
     |> assign(:account_action, :rotate)
     |> start_async(:rotate_credential, fn ->
       ProviderCredentials.rotate(
         scope,
         account.provider_account_id,
         credential.provider_credential_ref,
         opts
       )
     end)}
  end

  def handle_event("rotate-credential", _params, socket), do: {:noreply, socket}

  def handle_event("revoke-credential", _params, %{assigns: %{account_action: nil}} = socket) do
    %{current_scope: scope, provider_account: account, credential: credential} = socket.assigns
    opts = provider_account_live_opts()

    {:noreply,
     socket
     |> assign(:account_action, :revoke)
     |> start_async(:revoke_credential, fn ->
       ProviderCredentials.revoke(
         scope,
         account.provider_account_id,
         credential.provider_credential_ref,
         opts
       )
     end)}
  end

  def handle_event("revoke-credential", _params, socket), do: {:noreply, socket}

  def handle_event("grant-mission", %{"grant" => params}, socket) do
    %{current_scope: scope, provider_account: account} = socket.assigns

    attrs = %{
      restrictions: grant_restrictions(params),
      grant_reason: optional_text(params["grant_reason"])
    }

    case ProviderAccountGrants.grant(
           scope,
           params["mission_id"],
           account.provider_account_id,
           attrs
         ) do
      {:ok, _grant} ->
        {:noreply,
         socket
         |> reload_account()
         |> put_flash(:info, "Mission grant created.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, format_error(reason))}
    end
  end

  def handle_event("revoke-grant", %{"grant-id" => grant_id}, socket) do
    case ProviderAccountGrants.revoke(
           socket.assigns.current_scope,
           grant_id,
           "Revoked by organization administrator"
         ) do
      {:ok, _grant} ->
        {:noreply,
         socket
         |> reload_account()
         |> put_flash(:info, "Mission grant revoked. Existing contacts were retained for review.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, format_error(reason))}
    end
  end

  @impl true
  def handle_async(action, {:ok, {:ok, _result}}, socket)
      when action in [:validate_account, :rotate_credential, :revoke_credential] do
    {:noreply,
     socket
     |> assign(:account_action, nil)
     |> reload_account()
     |> put_flash(:info, action_success(action))}
  end

  def handle_async(_action, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:account_action, nil)
     |> reload_account()
     |> put_flash(:error, format_error(reason))}
  end

  def handle_async(_action, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:account_action, nil)
     |> put_flash(:error, "Provider Account operation stopped: #{inspect(reason)}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="provider-account-show-page" class="space-y-6">
        <.page_header
          title={@provider_account.display_name}
          subtitle={@provider_account.provider_account_id}
          breadcrumbs={[
            {"Provider Accounts", ~p"/provider-accounts"},
            {@provider_account.display_name, nil}
          ]}
        >
          <:title_suffix>
            <span class="font-mono text-xs text-base-content/60">
              config v{@account_version.version}
            </span>
          </:title_suffix>
          <:actions>
            <.button
              id="validate-provider-account-button"
              variant={:secondary}
              phx-click="validate-account"
              disabled={!is_nil(@account_action) or @credential.status == :revoked}
            >
              <.icon name="hero-shield-check" class="h-4 w-4" />
              {if(@account_action == :validate, do: "Validating…", else: "Validate")}
            </.button>
            <.button
              id="rotate-provider-credential-button"
              phx-click="rotate-credential"
              disabled={!is_nil(@account_action) or @credential.status == :revoked}
            >
              <.icon name="hero-arrow-path" class="h-4 w-4" />
              {if(@account_action == :rotate, do: "Rotating…", else: "Rotate")}
            </.button>
            <.button
              :if={@credential.status != :revoked}
              id="revoke-provider-credential-button"
              variant={:danger}
              phx-click="revoke-credential"
              data-confirm="Revoke this Provider Account credential? New provider operations will stop."
              disabled={!is_nil(@account_action)}
            >
              Revoke Credential
            </.button>
          </:actions>
        </.page_header>

        <div class="grid gap-3 md:grid-cols-4">
          <.stat_tile id="provider-account-health" label="Account Health" value={account_health(@provider_account)} />
          <.stat_tile id="provider-account-credential-status" label="Credential" value={credential_status(@credential)} />
          <.stat_tile id="provider-account-event-mode" label="Event Mode" value={humanize(@account_version.event_ingestion_mode)} />
          <.stat_tile id="provider-account-grant-count" label="Mission Grants" value={@active_grant_count} />
        </div>

        <div class="grid gap-4 xl:grid-cols-[minmax(0,1.4fr)_minmax(20rem,0.6fr)]">
          <div class="space-y-4">
            <.card
              id="provider-account-grants-card"
              heading="Mission Grants"
              subtitle="Explicit, versioned authorization. Mission restrictions may narrow but never widen organization guardrails."
              padding={:none}
            >
              <div id="provider-account-grants" phx-update="stream" class="divide-y divide-base-300">
                <div id="provider-account-grants-empty" class="hidden only:block p-5 text-sm text-base-content/60">
                  No missions have access to this account.
                </div>
                <div :for={{dom_id, grant} <- @streams.account_grants} id={dom_id} class="flex items-start justify-between gap-4 px-5 py-4">
                  <div>
                    <p class="font-medium">{mission_name(@mission_names, grant.mission_id)}</p>
                    <p class="mt-1 font-mono text-xs text-base-content/50">
                      grant v{grant.version} · account v{grant.provider_account_version}
                    </p>
                    <p :if={map_size(grant.restrictions) > 0} class="mt-2 text-xs text-base-content/60">
                      {restriction_summary(grant.restrictions)}
                    </p>
                  </div>
                  <div class="flex items-center gap-2">
                    <.status_badge status={grant_status(grant)} label={humanize(grant.lifecycle_state)} />
                    <.button
                      :if={grant.lifecycle_state == :active}
                      id={"revoke-grant-#{grant.provider_account_grant_id}"}
                      size={:xs}
                      variant={:danger}
                      phx-click="revoke-grant"
                      phx-value-grant-id={grant.provider_account_grant_id}
                      data-confirm="Revoke this mission grant? New operations will stop."
                    >
                      Revoke
                    </.button>
                  </div>
                </div>
              </div>
            </.card>

            <.card id="provider-account-grant-form-card" heading="Grant Mission Access" subtitle="Start from organization guardrails and optionally narrow the mission scope.">
              <.form for={@grant_form} id="provider-account-grant-form" phx-submit="grant-mission" class="space-y-4">
                <.input field={@grant_form[:mission_id]} type="select" label="Mission" options={@mission_options} required />
                <.input field={@grant_form[:allowed_services]} type="text" label="Allowed Services" placeholder="telemetry, tracking" />
                <.input field={@grant_form[:allowed_stations]} type="text" label="Allowed Stations" placeholder="station-alpha" />
                <.input field={@grant_form[:max_quota]} type="number" min="0" label="Maximum Quota" />
                <.input field={@grant_form[:grant_reason]} type="text" label="Grant Reason" placeholder="Flight operations authorization" />
                <div class="flex justify-end">
                  <.button id="grant-provider-account-button" type="submit">Grant Access</.button>
                </div>
              </.form>
            </.card>

            <.card id="provider-account-audit-card" heading="Recent Account Activity" subtitle="Bounded, append-only account and credential evidence." padding={:none}>
              <div id="provider-account-audit" phx-update="stream" class="divide-y divide-base-300">
                <div id="provider-account-audit-empty" class="hidden only:block p-5 text-sm text-base-content/60">No account activity recorded.</div>
                <div :for={{dom_id, entry} <- @streams.account_audit} id={dom_id} class="grid gap-2 px-5 py-3 sm:grid-cols-[10rem_minmax(0,1fr)_6rem] sm:items-center">
                  <time class="font-mono text-xs text-base-content/50">{timestamp_label(entry.recorded_at)}</time>
                  <span class="text-sm">{audit_label(entry.action)}</span>
                  <.status_badge status={audit_status(entry.outcome)} label={entry.outcome} />
                </div>
              </div>
            </.card>
          </div>

          <aside class="space-y-4">
            <.card id="provider-account-configuration" title="Effective Configuration">
              <div class="mt-3 divide-y divide-base-300">
                <.detail_row label="Provider" value={humanize(@account_version.provider_type)} />
                <.detail_row label="Region" value={@account_version.region_ref || "Not specified"} mono />
                <.detail_row label="Environment" value={@account_version.environment_ref} mono />
                <.detail_row label="Validated" value={timestamp_label(@provider_account.last_validated_at)} />
              </div>
            </.card>

            <.card id="provider-account-ingestion" title="Event Ingestion">
              <div class="mt-3 divide-y divide-base-300">
                <.detail_row label="Mode" value={humanize(@account_version.event_ingestion_mode)} />
                <div id="provider-account-ingestion-health">
                  <.detail_row label="Cursor health" value={@ingestion_summary.health} />
                </div>
                <div id="provider-account-ingestion-backlog">
                  <.detail_row label="Inbox backlog" value={to_string(@ingestion_summary.backlog)} mono />
                </div>
                <div id="provider-account-ingestion-quarantined">
                  <.detail_row label="Quarantined" value={to_string(@ingestion_summary.quarantined)} mono />
                </div>
                <div id="provider-account-ingestion-last-event">
                  <.detail_row label="Last provider event" value={timestamp_label(@ingestion_summary.last_event_at)} />
                </div>
              </div>
              <p class="mt-3 text-xs text-base-content/50">
                {@ingestion_summary.description}
              </p>
            </.card>

            <.card id="provider-account-guardrails" title="Organization Guardrails">
              <pre class="mt-3 max-h-72 overflow-auto bg-base-100/50 p-3 font-mono text-xs text-base-content/70">{Jason.encode!(@account_version.guardrails, pretty: true)}</pre>
            </.card>
          </aside>
        </div>

        <details id="provider-account-admin-diagnostics" class="rounded border border-base-300 bg-base-200/60 p-4 text-sm">
          <summary class="cursor-pointer hud-label hover:text-primary">Admin Diagnostics</summary>
          <div class="mt-4 grid gap-4 lg:grid-cols-2">
            <div class="divide-y divide-base-300">
              <.detail_row label="API base URL" value={@account_version.base_url} mono />
              <.detail_row label="Client adapter" value={Atom.to_string(@account_version.client_key)} mono />
              <.detail_row label="Credential registry version" value={"v#{@credential.registry_version}"} mono />
              <.detail_row label="Credential backend" value={humanize(@credential.backend_type)} />
            </div>
            <div class="divide-y divide-base-300">
              <.detail_row label="Account version" value={"v#{@account_version.version}"} mono />
              <.detail_row label="Credential status" value={humanize(@credential.status)} />
              <.detail_row label="Last resolved" value={timestamp_label(@credential.last_resolved_at)} />
              <.detail_row label="Last rotated" value={timestamp_label(@credential.last_rotated_at)} />
            </div>
          </div>
        </details>
      </div>
    </Layouts.app>
    """
  end

  defp load_account(socket, provider_account_id) do
    scope = socket.assigns.current_scope

    with {:ok, account, version} <- ProviderAccounts.fetch(scope, provider_account_id),
         {:ok, credential} <-
           ProviderCredentials.fetch(
             scope.organization_id,
             account.provider_account_id,
             version.credential_ref
           ),
         {:ok, grants} <- ProviderAccountGrants.list(scope, account.provider_account_id) do
      missions = Cadence.Missions.list_missions(scope.organization_id)
      mission_names = Map.new(missions, &{&1.mission_id, &1.display_name})
      granted_missions = MapSet.new(grants, & &1.mission_id)

      mission_options =
        missions
        |> Enum.reject(&MapSet.member?(granted_missions, &1.mission_id))
        |> Enum.map(&{&1.display_name, &1.mission_id})

      audits =
        ProviderAudit.list_entries(scope.organization_id,
          provider_account_id: account.provider_account_id,
          limit: 20
        )

      cursors =
        ProviderEventCursors.list(scope.organization_id,
          provider_account_id: account.provider_account_id
        )

      inbox_counts =
        ProviderEventInbox.counts(scope.organization_id, account.provider_account_id)

      {:ok,
       socket
       |> assign(:page_title, account.display_name)
       |> assign(:nav_item, :provider_accounts)
       |> assign(:provider_account, account)
       |> assign(:account_version, version)
       |> assign(:credential, credential)
       |> assign(:ingestion_summary, ingestion_summary(cursors, inbox_counts))
       |> assign(:account_action, nil)
       |> assign(:active_grant_count, Enum.count(grants, &(&1.lifecycle_state == :active)))
       |> assign(:mission_names, mission_names)
       |> assign(:mission_options, mission_options)
       |> assign(:grant_form, to_form(default_grant_params(), as: :grant))
       |> stream(:account_grants, grants, reset: true)
       |> stream(:account_audit, audits, reset: true)}
    end
  end

  defp reload_account(socket) do
    {:ok, socket} = load_account(socket, socket.assigns.provider_account.provider_account_id)
    socket
  end

  defp ingestion_summary(cursors, counts) do
    cursor = Enum.max_by(cursors, &cursor_sort_key/1, fn -> nil end)

    %{
      health: cursor_health(cursor),
      backlog:
        state_count(counts, "received") + state_count(counts, "processing") +
          state_count(counts, "reprocessing"),
      quarantined: state_count(counts, "quarantined"),
      last_event_at: cursor && cursor.last_event_at,
      description: cursor_description(cursor)
    }
  end

  defp cursor_sort_key(cursor),
    do: cursor.last_fetched_at || ~U[1970-01-01 00:00:00.000000Z]

  defp cursor_health(nil), do: "Not initialized"
  defp cursor_health(cursor), do: humanize(cursor.health)

  defp cursor_description(nil),
    do: "The durable cursor will initialize on the first polling cycle."

  defp cursor_description(cursor) do
    "#{cursor.channel_ref}/#{cursor.stream_ref} · last fetched #{timestamp_label(cursor.last_fetched_at)}"
  end

  defp state_count(counts, state), do: Map.get(counts, state, 0)

  defp default_grant_params do
    %{
      "mission_id" => "",
      "allowed_services" => "",
      "allowed_stations" => "",
      "max_quota" => "",
      "grant_reason" => ""
    }
  end

  defp grant_restrictions(params) do
    %{
      "allowed_services" => comma_list(params["allowed_services"]),
      "allowed_stations" => comma_list(params["allowed_stations"]),
      "max_quota" => nonnegative_integer(params["max_quota"])
    }
    |> Map.reject(fn {_key, value} -> value in [nil, []] end)
  end

  defp comma_list(value) do
    case optional_text(value) do
      nil -> []
      text -> text |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    end
  end

  defp nonnegative_integer(value) do
    case optional_text(value) do
      nil ->
        nil

      text ->
        case Integer.parse(text) do
          {number, ""} when number >= 0 -> number
          _other -> -1
        end
    end
  end

  defp optional_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      text -> text
    end
  end

  defp optional_text(_value), do: nil

  defp account_health(%{credential_status: :revoked}), do: "Blocked"
  defp account_health(%{last_validated_at: %DateTime{}}), do: "Validated"
  defp account_health(_account), do: "Not validated"

  defp credential_status(credential),
    do: "#{humanize(credential.status)} · v#{credential.registry_version}"

  defp mission_name(names, mission_id), do: Map.get(names, mission_id, mission_id)
  defp grant_status(%{lifecycle_state: :active}), do: :ready
  defp grant_status(_grant), do: :blocked

  defp restriction_summary(restrictions) do
    Enum.map_join(restrictions, " · ", fn {key, value} ->
      "#{humanize(key)}: #{restriction_value(value)}"
    end)
  end

  defp restriction_value(value) when is_list(value), do: Enum.join(value, ", ")
  defp restriction_value(value), do: to_string(value)

  defp audit_label(action), do: action |> String.replace("provider_", "") |> humanize()
  defp audit_status(outcome) when outcome in ["failed", "rejected", "blocked"], do: :blocked
  defp audit_status(_outcome), do: :ready

  defp humanize(value) when is_atom(value), do: value |> Atom.to_string() |> humanize()

  defp humanize(value) when is_binary(value) do
    value
    |> String.replace(["_", "."], " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp timestamp_label(nil), do: "Never"

  defp timestamp_label(%DateTime{} = timestamp),
    do: Calendar.strftime(timestamp, "%Y-%m-%d %H:%MZ")

  defp action_success(:validate_account), do: "Provider Account validated."

  defp action_success(:rotate_credential),
    do: "Credential rotated without changing its reference."

  defp action_success(:revoke_credential),
    do: "Credential revoked. New provider operations are blocked."

  defp provider_account_live_opts do
    Application.get_env(:cadence_web, :provider_account_live_opts, [])
  end

  defp format_error(%Ecto.Changeset{} = changeset),
    do: CadenceWeb.CommsComponents.format_error(changeset)

  defp format_error(reason), do: "Provider Account operation failed: #{inspect(reason)}"
end
