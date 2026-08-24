defmodule CadenceWeb.ProviderAccountNewLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.ExtensionCatalog
  alias Cadence.Extensions.Presentation.{ConfigurationDefinition, FieldDefinition}
  alias Cadence.GroundNetworks.{ProviderAccounts, ProviderCredentials}
  alias Cadence.Ids
  alias Phoenix.LiveView.JS

  @impl true
  def mount(_params, _session, socket) do
    account_id = Ids.new("provider_account")
    connector = default_connector()
    params = default_params(account_id, connector)

    {:ok,
     socket
     |> assign(:page_title, "New Provider Account")
     |> assign(:nav_item, :provider_accounts)
     |> assign(:provider_account_opts, provider_account_live_opts())
     |> assign(:provider_account_page, provider_account_page_dto())
     |> assign(:provider_account_form, provider_account_form_dto(params, connector))}
  end

  @impl true
  def handle_event("validate", %{"provider_account" => params}, socket) do
    connector = connector_for(params["provider_type"])

    params =
      params
      |> Map.put("provider_type", connector.form_value)
      |> Map.update("backend_type", "external", &supported_backend_type/1)
      |> with_connector_defaults(connector)

    {:noreply,
     assign(socket, :provider_account_form, provider_account_form_dto(params, connector))}
  end

  @impl true
  def handle_event("save", %{"provider_account" => params}, socket) do
    scope = socket.assigns.current_scope
    opts = socket.assigns.provider_account_opts

    with {:ok, credential_attrs} <- credential_attrs(params),
         {:ok, account_attrs} <- account_attrs(params),
         {:ok, _credential} <-
           ProviderCredentials.create(
             scope,
             params["provider_account_id"],
             credential_attrs,
             opts
           ),
         {:ok, account, _version} <- ProviderAccounts.create(scope, account_attrs, opts) do
      {:noreply, push_navigate(socket, to: ~p"/provider-accounts/#{account.provider_account_id}")}
    else
      {:error, reason} ->
        connector = connector_for(params["provider_type"])

        {:noreply,
         socket
         |> assign(:provider_account_form, provider_account_form_dto(params, connector))
         |> put_flash(:error, format_error(reason))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="provider-account-new-component"
        v-component="ProviderAccountNew"
        page={@provider_account_page}
        form={@provider_account_form}
        v-on:validate={JS.push("validate")}
        v-on:save={JS.push("save")}
        v-ssr={false}
        class="max-w-3xl space-y-6"
      />
    </Layouts.app>
    """
  end

  defp provider_account_page_dto do
    %{
      id: "provider-account-new-page",
      heading: "Register Provider Account",
      subtitle:
        "Create one organization-owned control-plane identity. Mission access is granted separately.",
      breadcrumbs: [
        %{label: "Provider Accounts", href: ~p"/provider-accounts"},
        %{label: "New", href: nil}
      ]
    }
  end

  defp provider_account_form_dto(params, connector) do
    backend_type = supported_backend_type(params["backend_type"])
    backend_presentations = backend_presentations_dto()
    backend_key_presentation = Map.fetch!(backend_presentations, backend_type)

    %{
      id: "provider-account-form",
      hidden_field_keys: ["provider_account_id", "credential_ref"],
      sections: %{
        network_identity: %{
          id: "provider-account-network-identity-section",
          number: "01",
          title: "Network Identity",
          field_keys: ["display_name", "provider_type"]
        },
        credential_registry: %{
          id: "provider-account-credential-registry-section",
          number: "03",
          title: "Credential Registry",
          field_keys: ["backend_type", "backend_key"]
        },
        organization_guardrails: %{
          id: "provider-account-organization-guardrails-section",
          number: "04",
          title: "Organization Guardrails",
          field_keys: [
            "allowed_services",
            "allowed_directions",
            "allowed_stations",
            "max_quota"
          ]
        }
      },
      fields: %{
        provider_account_id:
          form_field_dto(:provider_account_id, "hidden", nil, params,
            required: false
          ),
        credential_ref:
          form_field_dto(:credential_ref, "hidden", nil, params,
            required: false
          ),
        display_name:
          form_field_dto(:display_name, "text", "Display Name", params, required: true),
        provider_type:
          form_field_dto(:provider_type, "select", "Provider Type", params,
            required: true,
            options: provider_connector_options_dto()
          ),
        backend_type:
          form_field_dto(:backend_type, "select", "Secret Backend", params,
            required: true,
            options: backend_options_dto()
          ),
        backend_key:
          form_field_dto(:backend_key, "text", backend_key_presentation.label, params,
            required: true,
            placeholder: backend_key_presentation.placeholder,
            presentations: backend_presentations
          ),
        allowed_services:
          form_field_dto(:allowed_services, "text", "Allowed Services", params,
            placeholder: "telemetry, tracking"
          ),
        allowed_directions:
          form_field_dto(:allowed_directions, "text", "Allowed Directions", params,
            placeholder: "downlink, uplink"
          ),
        allowed_stations:
          form_field_dto(:allowed_stations, "text", "Allowed Stations", params,
            placeholder: "station-alpha, station-beta"
          ),
        max_quota:
          form_field_dto(:max_quota, "number", "Maximum Quota", params, min: 0)
      },
      connector: %{
        options: provider_connector_options_dto(),
        selected: provider_connector_summary_dto(connector),
        configuration: configuration_dto(connector.configuration, params),
        boundary: %{
          id: "provider-account-boundary-note",
          text:
            "This account owns provider endpoint and credential configuration. Missions receive versioned grants and never copy those values."
        }
      },
      credential_note: %{
        id: "provider-account-credential-note",
        text:
          "Cadence persists only a stable registry reference and backend locator. Secret material is never returned to this page."
      },
      actions: %{
        submit: %{id: "register-provider-account-button", label: "Register Account"},
        cancel: %{
          id: "cancel-provider-account-link",
          label: "Cancel",
          href: ~p"/provider-accounts"
        }
      }
    }
  end

  defp form_field_dto(field, type, label, params, opts) do
    key = Atom.to_string(field)

    %{
      key: key,
      id: "provider_account_#{key}",
      name: "provider_account[#{key}]",
      type: type,
      label: label,
      required: Keyword.get(opts, :required, false),
      placeholder: Keyword.get(opts, :placeholder),
      min: Keyword.get(opts, :min),
      max: Keyword.get(opts, :max),
      step: Keyword.get(opts, :step),
      options: Keyword.get(opts, :options, []),
      presentations: Keyword.get(opts, :presentations, %{}),
      value: string_param(params, key)
    }
  end

  defp provider_connector_summary_dto(connector) do
    %{
      id: "provider-connector-summary",
      form_value: connector.form_value,
      provider_type: Atom.to_string(connector.provider_type),
      client_key: Atom.to_string(connector.client_key),
      label: connector.label,
      description: connector.description
    }
  end

  defp configuration_dto(%ConfigurationDefinition{} = definition, params) do
    %{
      id: definition.id,
      kind: "provider_connector",
      description: definition.description,
      sections:
        Enum.map(
          definition.sections,
          &configuration_section_dto(&1, definition.id, params)
        )
    }
  end

  defp configuration_section_dto(section, definition_id, params) do
    %{
      id: section.id,
      fields_id: "#{section.id}-fields",
      number: section.number,
      title: section.title,
      description: section.description,
      fields: Enum.map(section.fields, &configuration_field_dto(&1, definition_id, params))
    }
  end

  defp configuration_field_dto(%FieldDefinition{} = field, definition_id, params) do
    key = Atom.to_string(field.field)
    dom_field = String.replace(key, "_", "-")

    %{
      key: key,
      wrapper_id: "#{definition_id}-field-#{dom_field}",
      id: "#{definition_id}-input-#{dom_field}",
      name: "provider_account[#{key}]",
      type: configuration_input_type(field.type),
      label: field.label,
      required: field.required,
      placeholder: field.placeholder,
      help: field.help,
      step: field.step,
      min: field.min,
      max: field.max,
      default: field.default,
      value: string_param(params, key, field.default),
      options: Enum.map(field.options, &option_dto/1),
      reference: reference_dto(field.reference),
      visible_when: visibility_dto(field.visible_when)
    }
  end

  defp reference_dto(nil), do: nil

  defp reference_dto(reference) do
    %{
      provider_id: reference.provider_id,
      version: reference.version,
      mode: Atom.to_string(reference.mode),
      result_limit: reference.result_limit
    }
  end

  defp visibility_dto(nil), do: nil

  defp visibility_dto(%{field: field, equals: expected}) do
    %{field: Atom.to_string(field), equals: presentation_value(expected)}
  end

  defp presentation_value(value) when is_binary(value), do: value
  defp presentation_value(value) when is_boolean(value), do: to_string(value)
  defp presentation_value(value) when is_atom(value), do: Atom.to_string(value)
  defp presentation_value(value) when is_number(value), do: to_string(value)
  defp presentation_value(value), do: inspect(value)

  defp configuration_input_type(:reference), do: "select"
  defp configuration_input_type(type), do: Atom.to_string(type)

  defp option_dto({label, value}), do: %{label: label, value: value, disabled: false}

  defp option_dto({label, value, opts}) do
    %{label: label, value: value, disabled: Keyword.get(opts, :disabled, false)}
  end

  defp provider_connector_options_dto do
    ExtensionCatalog.provider_connectors()
    |> Enum.map(&%{label: &1.label, value: &1.form_value, disabled: false})
    |> Enum.sort_by(&{&1.label, &1.value})
  end

  defp backend_options_dto do
    [
      %{label: "External secret manager", value: "external", disabled: false},
      %{label: "Local environment", value: "env", disabled: false}
    ]
  end

  defp backend_presentations_dto do
    %{
      "external" => %{
        label: "Secret Manager Key",
        placeholder: "providers/simulator/control-plane"
      },
      "env" => %{
        label: "Environment Variable",
        placeholder: "CADENCE_SIMULATOR_TOKEN"
      }
    }
  end

  defp default_params(account_id, connector) do
    %{
      "provider_account_id" => account_id,
      "credential_ref" => "provider_credential_#{account_id}",
      "provider_type" => connector.form_value,
      "backend_type" => "external",
      "backend_key" => "providers/simulator/control-plane"
    }
    |> Map.merge(connector.account_defaults)
    |> Map.merge(ConfigurationDefinition.default_params(connector.configuration))
  end

  defp with_connector_defaults(params, connector) do
    defaults =
      connector.account_defaults
      |> Map.merge(ConfigurationDefinition.default_params(connector.configuration))

    Map.merge(defaults, params)
  end

  defp credential_attrs(params) do
    with {:ok, credential_ref} <- required(params, "credential_ref", "Credential reference"),
         {:ok, backend_type} <- backend_type(params["backend_type"]),
         {:ok, backend_key} <- required(params, "backend_key", "Secret backend key") do
      {:ok,
       %{
         provider_credential_ref: credential_ref,
         backend_type: backend_type,
         backend_key: backend_key
       }}
    end
  end

  defp account_attrs(params) do
    with {:ok, connector} <- ExtensionCatalog.fetch_provider_connector(params["provider_type"]),
         {:ok, account_id} <- required(params, "provider_account_id", "Provider Account ID"),
         {:ok, display_name} <- required(params, "display_name", "Display name"),
         {:ok, base_url} <- required(params, "base_url", "Provider API base URL"),
         {:ok, environment_ref} <- required(params, "environment_ref", "Environment"),
         {:ok, credential_ref} <- required(params, "credential_ref", "Credential reference"),
         {:ok, quota} <- optional_nonnegative_integer(params["max_quota"]) do
      {:ok,
       %{
         provider_account_id: account_id,
         display_name: display_name,
         provider_type: connector.provider_type,
         client_key: connector.client_key,
         base_url: base_url,
         region_ref: optional_text(params["region_ref"]),
         environment_ref: environment_ref,
         credential_ref: credential_ref,
         event_ingestion_mode: params["event_ingestion_mode"],
         guardrails:
           compact(%{
             "allowed_services" => comma_list(params["allowed_services"]),
             "allowed_directions" => comma_list(params["allowed_directions"]),
             "allowed_stations" => comma_list(params["allowed_stations"]),
             "max_quota" => quota
           })
       }}
    end
  end

  defp backend_type("external"), do: {:ok, :external}
  defp backend_type("env"), do: {:ok, :env}
  defp backend_type(_value), do: {:error, "Select a supported secret backend."}

  defp supported_backend_type("env"), do: "env"
  defp supported_backend_type(_value), do: "external"

  defp required(params, key, label) do
    case optional_text(params[key]) do
      nil -> {:error, "#{label} is required."}
      value -> {:ok, value}
    end
  end

  defp optional_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp optional_text(_value), do: nil

  defp comma_list(value) do
    value
    |> optional_text()
    |> case do
      nil -> []
      text -> text |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    end
  end

  defp optional_nonnegative_integer(value) do
    case optional_text(value) do
      nil -> {:ok, nil}
      text -> parse_nonnegative_integer(text)
    end
  end

  defp parse_nonnegative_integer(text) do
    case Integer.parse(text) do
      {value, ""} when value >= 0 -> {:ok, value}
      _other -> {:error, "Maximum quota must be a non-negative whole number."}
    end
  end

  defp compact(map), do: Map.reject(map, fn {_key, value} -> value in [nil, []] end)

  defp provider_account_live_opts do
    Application.get_env(:cadence_web, :provider_account_live_opts, [])
  end

  defp format_error(%Ecto.Changeset{} = changeset),
    do: CadenceWeb.CommsComponents.format_error(changeset)

  defp format_error(reason), do: "Could not register provider account: #{inspect(reason)}"

  defp connector_for(form_value) do
    case ExtensionCatalog.fetch_provider_connector(form_value) do
      {:ok, connector} -> connector
      {:error, _reason} -> default_connector()
    end
  end

  defp default_connector do
    {:ok, connector} = ExtensionCatalog.fetch_provider_connector("simulator")
    connector
  end

  defp string_param(params, key, default \\ "") when is_map(params) do
    case Map.get(params, key, default) do
      value when is_binary(value) -> value
      _other -> default
    end
  end

  defp string_param(_params, _key, default), do: default
end
