defmodule CadenceWeb.ApplicationContributions.OrganizationAdminProviders.ProviderAccountShow do
  @moduledoc false

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.GroundNetworks.{
    ProviderAccountGrants,
    ProviderAccounts,
    ProviderAudit,
    ProviderCredentials,
    ProviderEventCursors,
    ProviderEventInbox
  }

  @spec props(Cadence.Auth.Scope.t(), binary()) :: {:ok, map()} | {:error, term()}
  def props(%Cadence.Auth.Scope{} = scope, provider_account_id)
      when is_binary(provider_account_id) do
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

      inbox_counts = ProviderEventInbox.counts(scope.organization_id, account.provider_account_id)

      grant_rows =
        grants
        |> Enum.map(&grant_dto(&1, mission_names))
        |> Enum.map(&Map.put(&1, :__dom_id, "account-grant-#{&1.id}"))

      audit_rows =
        audits
        |> Enum.map(&audit_dto/1)
        |> Enum.map(&Map.put(&1, :__dom_id, "account-audit-#{&1.id}"))

      {:ok,
       %{
         page: provider_account_page_dto(account, version),
         actions: account_actions_dto(nil, credential),
         stats:
           account_stats_dto(
             account,
             version,
             credential,
             Enum.count(grants, &(&1.lifecycle_state == :active))
           ),
         grant_form: grant_form_dto(mission_options),
         configuration: configuration_dto(account, version),
         ingestion: ingestion_dto(version, ingestion_summary(cursors, inbox_counts)),
         guardrails: guardrails_dto(version.guardrails),
         diagnostics: diagnostics_dto(version, credential),
         account_grants: grant_rows,
         account_audit: audit_rows
       }}
    end
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

  defp cursor_sort_key(cursor), do: cursor.last_fetched_at || ~U[1970-01-01 00:00:00.000000Z]
  defp cursor_health(nil), do: "Not initialized"
  defp cursor_health(cursor), do: humanize(cursor.health)

  defp cursor_description(nil),
    do: "The durable cursor will initialize on the first polling cycle."

  defp cursor_description(cursor),
    do:
      "#{cursor.channel_ref}/#{cursor.stream_ref} · last fetched #{timestamp_label(cursor.last_fetched_at)}"

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
        empty: %{id: "provider-account-audit-empty", text: "No account activity recorded."}
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
      stat_dto("provider-account-credential-status", "Credential", credential_status(credential)),
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
        detail_dto("Cursor health", summary.health, false, "provider-account-ingestion-health"),
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

  defp guardrails_dto(guardrails),
    do: %{
      id: "provider-account-guardrails",
      title: "Organization Guardrails",
      json: Jason.encode!(guardrails, pretty: true)
    }

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

  defp detail_dto(label, value, mono \\ false, wrapper_id \\ nil),
    do: %{label: label, value: value || "—", mono: mono, wrapper_id: wrapper_id}

  defp default_grant_params,
    do: %{
      "mission_id" => "",
      "allowed_services" => "",
      "allowed_stations" => "",
      "max_quota" => "",
      "grant_reason" => ""
    }

  defp account_health(%{credential_status: :revoked}), do: "Blocked"
  defp account_health(%{last_validated_at: %DateTime{}}), do: "Validated"
  defp account_health(_account), do: "Not validated"

  defp credential_status(credential),
    do: "#{humanize(credential.status)} · v#{credential.registry_version}"

  defp mission_name(names, mission_id), do: Map.get(names, mission_id, mission_id)
  defp grant_status(%{lifecycle_state: :active}), do: :ready
  defp grant_status(_grant), do: :blocked

  defp restriction_summary(restrictions),
    do:
      Enum.map_join(restrictions, " · ", fn {key, value} ->
        "#{humanize(key)}: #{restriction_value(value)}"
      end)

  defp restriction_value(value) when is_list(value), do: Enum.join(value, ", ")
  defp restriction_value(value), do: to_string(value)
  defp audit_label(action), do: action |> String.replace("provider_", "") |> humanize()
  defp audit_status(outcome) when outcome in ["failed", "rejected", "blocked"], do: :blocked
  defp audit_status(_outcome), do: :ready
  defp humanize(value) when is_atom(value), do: value |> Atom.to_string() |> humanize()

  defp humanize(value) when is_binary(value),
    do:
      value
      |> String.replace(["_", "."], " ")
      |> String.split()
      |> Enum.map_join(" ", &String.capitalize/1)

  defp timestamp_label(nil), do: "Never"

  defp timestamp_label(%DateTime{} = timestamp),
    do: Calendar.strftime(timestamp, "%Y-%m-%d %H:%MZ")
end
