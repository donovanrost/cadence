defmodule CadenceWeb.CommsProviderNewLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.Management.Providers

  alias Cadence.GroundNetworks.{
    MissionProvider,
    ProviderAccountGrants,
    ProviderAccounts
  }

  alias Phoenix.LiveView.JS

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    bindings = granted_bindings(scope.organization_id, mission.mission_id)
    default_grant_id = bindings |> List.first() |> binding_value(:grant_id, "")
    params = default_params(default_grant_id)
    selected_binding = find_binding(bindings, default_grant_id)

    {:ok,
     socket
     |> assign(:page_title, "New Mission Provider")
     |> assign(:nav_item, :comms_providers)
     |> assign(:provider_bindings, bindings)
     |> assign(:page, page_dto(mission))
     |> assign(:accounts, accounts_dto(bindings, selected_binding))
     |> assign(:notes, notes_dto())
     |> assign(:form, form_dto(params, mission, bindings))}
  end

  @impl true
  def handle_event("validate", %{"provider" => params}, socket) do
    {:noreply, sync_form(socket, params)}
  end

  @impl true
  def handle_event("save", %{"provider" => params}, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    socket = sync_form(socket, params)

    with {:ok, binding} <- selected_binding(socket.assigns.provider_bindings, params),
         {:ok, attrs} <- provider_attrs(params, mission.mission_id, binding),
         provider <- MissionProvider.new(attrs),
         {:ok, provider} <- Providers.persist_provider(scope, provider) do
      {:noreply,
       push_navigate(socket,
         to: ~p"/missions/#{mission.mission_id}/comms/providers/#{provider.provider_id}"
       )}
    else
      {:error, message} when is_binary(message) ->
        {:noreply, put_flash(socket, :error, message)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, format_error(reason))}
    end
  rescue
    error in ArgumentError ->
      {:noreply, put_flash(socket, :error, error.message)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="comms-provider-new-component"
        v-component="CommsProviderNew"
        page={@page}
        accounts={@accounts}
        notes={@notes}
        form={@form}
        v-on:validate={JS.push("validate")}
        v-on:save={JS.push("save")}
        v-ssr={false}
        class="max-w-3xl space-y-6"
      />
    </Layouts.app>
    """
  end

  defp sync_form(socket, params) do
    bindings = socket.assigns.provider_bindings
    selected_binding = find_binding(bindings, params["provider_account_grant_id"])

    socket
    |> assign(:accounts, accounts_dto(bindings, selected_binding))
    |> assign(:form, form_dto(params, socket.assigns.current_mission, bindings))
  end

  defp page_dto(mission) do
    %{
      id: "comms-provider-new-page",
      title: "New Mission Provider",
      subtitle:
        "Bind an organization-approved ground network account and define this mission's delivery tolerances.",
      breadcrumbs: [
        %{label: mission.display_name, href: ~p"/missions/#{mission.mission_id}"},
        %{label: "Comms", href: ~p"/missions/#{mission.mission_id}/comms"},
        %{label: "Providers", href: ~p"/missions/#{mission.mission_id}/comms/providers"},
        %{label: "New", href: nil}
      ]
    }
  end

  defp accounts_dto(bindings, selected_binding) do
    %{
      empty: bindings == [],
      options: Enum.map(bindings, &binding_option_dto/1),
      selected: account_summary_dto(selected_binding),
      empty_state: %{
        id: "mission-provider-no-grants",
        heading: "This mission has no Provider Account grants.",
        message:
          "An organization administrator must grant an account before mission setup can continue.",
        action: %{
          id: "open-provider-accounts-link",
          label: "Open Provider Accounts",
          href: ~p"/provider-accounts"
        }
      }
    }
  end

  defp account_summary_dto(nil), do: nil

  defp account_summary_dto(binding) do
    %{
      id: "mission-provider-account-summary",
      ownership_label: "Organization-owned configuration",
      display_name: binding.account.display_name,
      version_label:
        "account v#{binding.account_version.version} · grant v#{binding.grant.version}",
      badge: %{status: "ready", label: "Granted"},
      restrictions: [
        %{
          label: "Account Guardrails",
          summary: restriction_summary(binding.account_version.guardrails)
        },
        %{
          label: "Mission Restrictions",
          summary: restriction_summary(binding.grant.restrictions)
        }
      ]
    }
  end

  defp notes_dto do
    %{
      secret_boundary: %{
        id: "mission-provider-secret-boundary-note",
        text:
          "Provider endpoint, credential, and environment values remain organization-owned and are never exposed to this mission form."
      },
      resource_boundary: %{
        id: "mission-provider-resource-guardrail-note",
        text:
          "Leave blank to inherit the grant. Any listed resources must be inside both the account guardrails and the mission grant."
      }
    }
  end

  defp form_dto(params, mission, bindings) do
    policy_mode = string_param(params, "policy_mode")

    %{
      id: "mission-provider-form",
      sections: %{
        binding:
          section_dto(
            "mission-provider-binding-section",
            "01",
            "Mission Binding",
            ["display_name", "provider_account_grant_id"]
          ),
        resource_scope:
          section_dto(
            "mission-provider-resource-scope-section",
            "02",
            "Mission Resource Scope",
            ["permitted_resource_refs"]
          ),
        delivery_policy:
          section_dto(
            "mission-provider-delivery-policy-section",
            "03",
            "Delivery Change Policy",
            ["policy_mode", "deadline_behavior"]
          )
      },
      fields: fields_dto(params, bindings),
      conditional: %{
        approval_guidance: %{
          id: "mission-provider-approval-policy-guidance",
          active: policy_mode == "approval_required",
          visible_when: %{field: "policy_mode", equals: "approval_required"},
          text:
            "Provider facts are still recorded immediately, but actionable schedule or resource changes wait for an authorized operator decision."
        },
        bounded_policy: %{
          id: "mission-provider-bounded-policy-fields",
          active: policy_mode == "bounded_automatic",
          visible_when: %{field: "policy_mode", equals: "bounded_automatic"},
          field_keys: [
            "maximum_earlier_start_shift_seconds",
            "maximum_later_start_shift_seconds",
            "maximum_earlier_end_shift_seconds",
            "maximum_later_end_shift_seconds",
            "minimum_retained_duration_seconds",
            "approved_station_substitutions"
          ]
        }
      },
      actions: %{
        submit: %{id: "create-mission-provider-button", label: "Create Mission Provider"},
        cancel: %{
          id: "cancel-mission-provider-link",
          label: "Cancel",
          href: ~p"/missions/#{mission.mission_id}/comms/providers"
        }
      }
    }
  end

  defp section_dto(id, number, title, field_keys) do
    %{id: id, number: number, title: title, field_keys: field_keys}
  end

  defp fields_dto(params, bindings) do
    %{
      display_name:
        field_dto(:display_name, "text", "Display Name", params, required: true),
      provider_account_grant_id:
        field_dto(
          :provider_account_grant_id,
          "select",
          "Granted Provider Account",
          params,
          required: true,
          options: Enum.map(bindings, &binding_option_dto/1)
        ),
      permitted_resource_refs:
        field_dto(
          :permitted_resource_refs,
          "text",
          "Permitted Stations or Service Pools",
          params,
          placeholder: "station-alpha, station-beta"
        ),
      policy_mode:
        field_dto(:policy_mode, "select", "Material Change Handling", params,
          required: true,
          options: [
            option_dto("Require approval for every material change", "approval_required"),
            option_dto("Automatically accept changes within limits", "bounded_automatic")
          ]
        ),
      maximum_earlier_start_shift_seconds:
        field_dto(
          :maximum_earlier_start_shift_seconds,
          "number",
          "Max Earlier Start Shift (seconds)",
          params,
          min: 0
        ),
      maximum_later_start_shift_seconds:
        field_dto(
          :maximum_later_start_shift_seconds,
          "number",
          "Max Later Start Shift (seconds)",
          params,
          min: 0
        ),
      maximum_earlier_end_shift_seconds:
        field_dto(
          :maximum_earlier_end_shift_seconds,
          "number",
          "Max Earlier End Shift (seconds)",
          params,
          min: 0
        ),
      maximum_later_end_shift_seconds:
        field_dto(
          :maximum_later_end_shift_seconds,
          "number",
          "Max Later End Shift (seconds)",
          params,
          min: 0
        ),
      minimum_retained_duration_seconds:
        field_dto(
          :minimum_retained_duration_seconds,
          "number",
          "Minimum Retained Duration (seconds)",
          params,
          min: 1
        ),
      approved_station_substitutions:
        field_dto(
          :approved_station_substitutions,
          "text",
          "Approved Station Substitutions",
          params,
          placeholder: "station-alpha, station-beta"
        ),
      deadline_behavior:
        field_dto(:deadline_behavior, "select", "No-response Deadline Behavior", params,
          required: true,
          options: [
            option_dto("Retain last accepted schedule", "retain_last_accepted"),
            option_dto("Cancel if still actionable", "cancel_if_actionable")
          ]
        )
    }
  end

  defp field_dto(field, type, label, params, opts) do
    key = Atom.to_string(field)

    %{
      key: key,
      id: "provider_#{key}",
      name: "provider[#{key}]",
      type: type,
      label: label,
      required: Keyword.get(opts, :required, false),
      placeholder: Keyword.get(opts, :placeholder),
      min: Keyword.get(opts, :min),
      options: Keyword.get(opts, :options, []),
      value: string_param(params, key)
    }
  end

  defp binding_option_dto(binding) do
    option_dto(
      "#{binding.account.display_name} · account v#{binding.account_version.version} · grant v#{binding.grant.version}",
      binding.grant_id
    )
  end

  defp option_dto(label, value), do: %{label: label, value: value}

  defp string_param(params, key) when is_map(params) do
    case Map.get(params, key) do
      value when is_binary(value) -> value
      _other -> ""
    end
  end

  defp granted_bindings(organization_id, mission_id) do
    organization_id
    |> ProviderAccountGrants.list_for_mission(mission_id)
    |> Enum.flat_map(&granted_binding(organization_id, &1))
  end

  defp granted_binding(organization_id, grant) do
    with {:ok, account, _active_version} <-
           ProviderAccounts.fetch_for_system(organization_id, grant.provider_account_id),
         {:ok, account_version} <-
           ProviderAccounts.fetch_version(
             organization_id,
             grant.provider_account_id,
             grant.provider_account_version
           ) do
      [
        %{
          grant_id: grant.provider_account_grant_id,
          grant: grant,
          account: account,
          account_version: account_version
        }
      ]
    else
      {:error, _reason} -> []
    end
  end

  defp default_params(grant_id) do
    %{
      "display_name" => "Ground Network Simulator",
      "provider_account_grant_id" => grant_id,
      "permitted_resource_refs" => "",
      "policy_mode" => "approval_required",
      "maximum_earlier_start_shift_seconds" => "0",
      "maximum_later_start_shift_seconds" => "0",
      "maximum_earlier_end_shift_seconds" => "0",
      "maximum_later_end_shift_seconds" => "0",
      "minimum_retained_duration_seconds" => "",
      "approved_station_substitutions" => "",
      "deadline_behavior" => "retain_last_accepted"
    }
  end

  defp selected_binding(bindings, params) do
    case find_binding(bindings, params["provider_account_grant_id"]) do
      nil -> {:error, "Select a Provider Account granted to this mission."}
      binding -> {:ok, binding}
    end
  end

  defp find_binding(bindings, grant_id), do: Enum.find(bindings, &(&1.grant_id == grant_id))

  defp provider_attrs(params, mission_id, binding) do
    with {:ok, display_name} <- required_text(params["display_name"], "Display name is required."),
         permitted_resources = comma_list(params["permitted_resource_refs"]),
         :ok <- validate_resources(permitted_resources, binding),
         {:ok, delivery_policy} <- delivery_policy(params) do
      version = binding.account_version
      grant = binding.grant

      {:ok,
       %{
         mission_id: mission_id,
         display_name: display_name,
         provider_account_id: version.provider_account_id,
         provider_account_version: version.version,
         provider_account_grant_id: grant.provider_account_grant_id,
         provider_account_grant_version: grant.version,
         provider_type: version.provider_type,
         client_key: version.client_key,
         base_url: version.base_url,
         credential_ref: version.credential_ref,
         environment_ref: version.environment_ref,
         permitted_resource_refs: permitted_resources,
         delivery_policy_document: delivery_policy
       }}
    end
  end

  defp delivery_policy(%{"policy_mode" => "approval_required"} = params) do
    {:ok,
     %{
       "mode" => "approval_required",
       "changes_always_requiring_approval" => ["schedule", "resource", "capacity", "cost"],
       "deadline_behavior" => params["deadline_behavior"]
     }}
  end

  defp delivery_policy(%{"policy_mode" => "bounded_automatic"} = params) do
    fields = [
      "maximum_earlier_start_shift_seconds",
      "maximum_later_start_shift_seconds",
      "maximum_earlier_end_shift_seconds",
      "maximum_later_end_shift_seconds",
      "minimum_retained_duration_seconds"
    ]

    with {:ok, values} <- parse_policy_numbers(params, fields) do
      {:ok,
       values
       |> Map.put("mode", "bounded_automatic")
       |> Map.put("deadline_behavior", params["deadline_behavior"])
       |> Map.put(
         "approved_station_substitutions",
         comma_list(params["approved_station_substitutions"])
       )}
    end
  end

  defp delivery_policy(_params), do: {:error, "Select a delivery change policy."}

  defp parse_policy_numbers(params, fields) do
    Enum.reduce_while(fields, {:ok, %{}}, fn field, {:ok, values} ->
      case optional_nonnegative_integer(params[field]) do
        {:ok, nil} -> {:cont, {:ok, values}}
        {:ok, value} -> {:cont, {:ok, Map.put(values, field, value)}}
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
  end

  defp validate_resources([], _binding), do: :ok

  defp validate_resources(resources, binding) do
    allowed =
      Map.get(binding.grant.restrictions, "allowed_stations") ||
        Map.get(binding.account_version.guardrails, "allowed_stations")

    if is_nil(allowed) or MapSet.subset?(MapSet.new(resources), MapSet.new(allowed)) do
      :ok
    else
      {:error, "Permitted resources must stay within the Provider Account grant."}
    end
  end

  defp binding_value(nil, _key, default), do: default
  defp binding_value(binding, key, _default), do: Map.fetch!(binding, key)

  defp restriction_summary(restrictions) when map_size(restrictions) == 0,
    do: "No additional limits"

  defp restriction_summary(restrictions) do
    Enum.map_join(restrictions, " · ", fn {key, value} ->
      "#{humanize(key)}: #{restriction_value(value)}"
    end)
  end

  defp restriction_value(value) when is_list(value), do: Enum.join(value, ", ")
  defp restriction_value(value), do: to_string(value)

  defp required_text(value, message) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, message}
      trimmed -> {:ok, trimmed}
    end
  end

  defp required_text(_value, message), do: {:error, message}

  defp comma_list(value) when is_binary(value) do
    value |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  defp comma_list(_value), do: []

  defp optional_nonnegative_integer(value) when value in [nil, ""], do: {:ok, nil}

  defp optional_nonnegative_integer(value) do
    case Integer.parse(to_string(value)) do
      {number, ""} when number >= 0 -> {:ok, number}
      _other -> {:error, "Delivery policy limits must be non-negative whole numbers."}
    end
  end

  defp humanize(value) do
    value
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_error(%Ecto.Changeset{} = changeset),
    do: CadenceWeb.CommsComponents.format_error(changeset)

  defp format_error(reason), do: "Could not create provider: #{inspect(reason)}"
end
