defmodule CadenceWeb.ProviderAccountShowLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.Control.Providers, as: ControlProviders

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
      |> assign(:provider_account_opts, provider_account_live_opts())
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
    opts = socket.assigns.provider_account_opts

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
    opts = socket.assigns.provider_account_opts

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
    opts = socket.assigns.provider_account_opts

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
    case ControlProviders.revoke_account_grant(
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
      <.vue
        id="provider-account-show-component"
        v-component="FederatedFullPageSurface"
        application_key="organization_admin"
        surface_id="provider_account_show"
        host_scope="organization"
        organization_id={@current_scope.organization.organization_id}
        v-ssr={false}
        class="contents"
      />
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

      grant_rows = Enum.map(grants, &grant_dto(&1, mission_names))
      audit_rows = Enum.map(audits, &audit_dto/1)

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
       |> assign(:grant_form, grant_form_dto(mission_options))
       |> stream(:account_grants, grant_rows, reset: true)
       |> stream(:account_audit, audit_rows, reset: true)}
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

  defp provider_account_page_dto(account, version) do
    %{
      id: "provider-account-show-page",
      header: %{
        title: account.display_name,
        subtitle: account.provider_account_id,
        config_label: "config v#{version.version}",
        breadcrumbs: [
          %{label: "Provider Accounts", href: ~p"/provider-accounts"},
          %{label: account.display_name, href: nil}
        ]
      },
      grants: %{
        card_id: "provider-account-grants-card",
        heading: "Mission Grants",
        subtitle:
          "Explicit, versioned authorization. Mission restrictions may narrow but never widen organization guardrails.",
        stream_id: "provider-account-grants",
        empty: %{
          id: "provider-account-grants-empty",
          text: "No missions have access to this account."
        }
      },
      grant_form_card: %{
        id: "provider-account-grant-form-card",
        heading: "Grant Mission Access",
        subtitle: "Start from organization guardrails and optionally narrow the mission scope."
      },
      audit: %{
        card_id: "provider-account-audit-card",
        heading: "Recent Account Activity",
        subtitle: "Bounded, append-only account and credential evidence.",
        stream_id: "provider-account-audit",
        empty: %{
          id: "provider-account-audit-empty",
          text: "No account activity recorded."
        }
      }
    }
  end

  defp account_actions_dto(account_action, credential) do
    busy? = not is_nil(account_action)
    revoked? = credential.status == :revoked

    %{
      validate: %{
        id: "validate-provider-account-button",
        icon: "hero-shield-check",
        label: if(account_action == :validate, do: "Validating…", else: "Validate"),
        disabled: busy? or revoked?,
        payload: %{}
      },
      rotate: %{
        id: "rotate-provider-credential-button",
        icon: "hero-arrow-path",
        label: if(account_action == :rotate, do: "Rotating…", else: "Rotate"),
        disabled: busy? or revoked?,
        payload: %{}
      },
      revoke:
        if(revoked?,
          do: nil,
          else: %{
            id: "revoke-provider-credential-button",
            label: "Revoke Credential",
            confirm:
              "Revoke this Provider Account credential? New provider operations will stop.",
            disabled: busy?,
            payload: %{}
          }
        )
    }
  end

  defp account_stats_dto(account, version, credential, active_grant_count) do
    [
      stat_dto("provider-account-health", "Account Health", account_health(account)),
      stat_dto(
        "provider-account-credential-status",
        "Credential",
        credential_status(credential)
      ),
      stat_dto(
        "provider-account-event-mode",
        "Event Mode",
        humanize(version.event_ingestion_mode)
      ),
      stat_dto("provider-account-grant-count", "Mission Grants", active_grant_count)
    ]
  end

  defp stat_dto(id, label, value), do: %{id: id, label: label, value: value}

  defp grant_form_dto(mission_options) do
    params = default_grant_params()

    %{
      id: "provider-account-grant-form",
      values: params,
      fields: %{
        mission_id:
          grant_field_dto(:mission_id, "select", "Mission", params,
            required: true,
            options:
              Enum.map(mission_options, fn {label, value} ->
                %{label: label, value: value, disabled: false}
              end)
          ),
        allowed_services:
          grant_field_dto(:allowed_services, "text", "Allowed Services", params,
            placeholder: "telemetry, tracking"
          ),
        allowed_stations:
          grant_field_dto(:allowed_stations, "text", "Allowed Stations", params,
            placeholder: "station-alpha"
          ),
        max_quota: grant_field_dto(:max_quota, "number", "Maximum Quota", params, min: 0),
        grant_reason:
          grant_field_dto(:grant_reason, "text", "Grant Reason", params,
            placeholder: "Flight operations authorization"
          )
      },
      action: %{id: "grant-provider-account-button", label: "Grant Access"}
    }
  end

  defp grant_field_dto(field, type, label, params, opts) do
    key = Atom.to_string(field)

    %{
      key: key,
      id: "grant_#{key}",
      name: "grant[#{key}]",
      type: type,
      label: label,
      value: Map.fetch!(params, key),
      required: Keyword.get(opts, :required, false),
      min: Keyword.get(opts, :min),
      placeholder: Keyword.get(opts, :placeholder),
      options: Keyword.get(opts, :options, [])
    }
  end

  defp grant_dto(grant, mission_names) do
    %{
      id: grant.provider_account_grant_id,
      provider_account_grant_id: grant.provider_account_grant_id,
      mission_name: mission_name(mission_names, grant.mission_id),
      version_label: "grant v#{grant.version} · account v#{grant.provider_account_version}",
      restriction_summary:
        if(map_size(grant.restrictions) > 0,
          do: restriction_summary(grant.restrictions),
          else: nil
        ),
      lifecycle: %{
        status: grant |> grant_status() |> Atom.to_string(),
        label: humanize(grant.lifecycle_state)
      },
      revoke:
        if(grant.lifecycle_state == :active,
          do: %{
            id: "revoke-grant-#{grant.provider_account_grant_id}",
            label: "Revoke",
            confirm: "Revoke this mission grant? New operations will stop.",
            payload: %{"grant-id" => grant.provider_account_grant_id}
          },
          else: nil
        )
    }
  end

  defp audit_dto(entry) do
    %{
      id: entry.provider_audit_entry_id,
      provider_audit_entry_id: entry.provider_audit_entry_id,
      recorded_at: timestamp_label(entry.recorded_at),
      action: audit_label(entry.action),
      outcome: %{
        status: entry.outcome |> audit_status() |> Atom.to_string(),
        label: entry.outcome
      }
    }
  end

  defp configuration_dto(account, version) do
    %{
      id: "provider-account-configuration",
      title: "Effective Configuration",
      rows: [
        detail_dto("Provider", humanize(version.provider_type)),
        detail_dto("Region", version.region_ref || "Not specified", true),
        detail_dto("Environment", version.environment_ref, true),
        detail_dto("Validated", timestamp_label(account.last_validated_at))
      ]
    }
  end

  defp ingestion_dto(version, summary) do
    %{
      id: "provider-account-ingestion",
      title: "Event Ingestion",
      rows: [
        detail_dto("Mode", humanize(version.event_ingestion_mode)),
        detail_dto(
          "Cursor health",
          summary.health,
          false,
          "provider-account-ingestion-health"
        ),
        detail_dto(
          "Inbox backlog",
          to_string(summary.backlog),
          true,
          "provider-account-ingestion-backlog"
        ),
        detail_dto(
          "Quarantined",
          to_string(summary.quarantined),
          true,
          "provider-account-ingestion-quarantined"
        ),
        detail_dto(
          "Last provider event",
          timestamp_label(summary.last_event_at),
          false,
          "provider-account-ingestion-last-event"
        )
      ],
      description: summary.description
    }
  end

  defp guardrails_dto(guardrails) do
    %{
      id: "provider-account-guardrails",
      title: "Organization Guardrails",
      json: Jason.encode!(guardrails, pretty: true)
    }
  end

  defp diagnostics_dto(version, credential) do
    %{
      id: "provider-account-admin-diagnostics",
      title: "Admin Diagnostics",
      columns: [
        [
          detail_dto("API base URL", version.base_url, true),
          detail_dto("Client adapter", Atom.to_string(version.client_key), true),
          detail_dto("Credential registry version", "v#{credential.registry_version}", true),
          detail_dto("Credential backend", humanize(credential.backend_type))
        ],
        [
          detail_dto("Account version", "v#{version.version}", true),
          detail_dto("Credential status", humanize(credential.status)),
          detail_dto("Last resolved", timestamp_label(credential.last_resolved_at)),
          detail_dto("Last rotated", timestamp_label(credential.last_rotated_at))
        ]
      ]
    }
  end

  defp detail_dto(label, value, mono \\ false, wrapper_id \\ nil) do
    %{label: label, value: value || "—", mono: mono, wrapper_id: wrapper_id}
  end

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
