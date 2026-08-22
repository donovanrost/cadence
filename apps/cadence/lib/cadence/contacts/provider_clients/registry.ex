defmodule Cadence.Contacts.ProviderClients.Registry do
  @moduledoc "Compile-time registry for provider control-plane clients."

  alias Cadence.Contacts.ProviderClients.Definition
  alias Cadence.Contacts.ProviderClients.SimulatorHTTP

  alias Cadence.Extensions.Presentation.{
    ConfigurationDefinition,
    FieldDefinition,
    SectionDefinition
  }

  alias Cadence.GroundNetworks.ProviderContext

  @type definition_fetch_error ::
          {:unknown_provider_connector, term()}
          | {:unsupported_provider_connector_version, term(), term()}
          | {:invalid_provider_connector_definition, term()}

  @spec all() :: [Definition.t()]
  def all, do: [simulator_definition()]

  @spec available() :: [Definition.t()]
  def available, do: Enum.filter(all(), &(Definition.validate(&1) == :ok))

  @spec default_definition() :: Definition.t()
  def default_definition, do: List.first(available())

  @spec form_options() :: [{binary(), binary()}]
  def form_options do
    available()
    |> Enum.map(&{&1.label, &1.form_value})
    |> Enum.sort()
  end

  @spec fetch_definition(binary() | atom(), pos_integer() | :latest | nil) ::
          {:ok, Definition.t()} | {:error, definition_fetch_error()}
  def fetch_definition(value, version \\ :latest)

  def fetch_definition(value, version) when is_binary(value) or is_atom(value) do
    case find_definition(value) do
      %Definition{} = definition when version in [:latest, nil, definition.version] ->
        validate_definition(definition, value)

      %Definition{} ->
        {:error, {:unsupported_provider_connector_version, value, version}}

      nil ->
        {:error, {:unknown_provider_connector, value}}
    end
  end

  def fetch_definition(value, _version), do: {:error, {:unknown_provider_connector, value}}

  @spec fetch(ProviderContext.t()) :: {:ok, module()} | {:error, term()}
  def fetch(%ProviderContext{client_key: client_key}) do
    case Enum.find(available(), &(Atom.to_string(&1.client_key) == client_key)) do
      %Definition{module: module} -> {:ok, module}
      nil -> {:error, {:unknown_provider_client, client_key}}
    end
  end

  @spec fetch_webhook_authenticator(atom()) :: {:ok, module()} | {:error, term()}
  def fetch_webhook_authenticator(provider_type) when is_atom(provider_type),
    do: {:error, :provider_webhook_authenticator_not_configured}

  defp find_definition(value) when is_binary(value),
    do: Enum.find(all(), &(&1.form_value == value))

  defp find_definition(value) when is_atom(value),
    do: Enum.find(all(), &(&1.provider_type == value))

  defp validate_definition(definition, value) do
    case Definition.validate(definition) do
      :ok ->
        {:ok, definition}

      {:error, :invalid_provider_connector_definition} ->
        {:error, {:invalid_provider_connector_definition, value}}
    end
  end

  defp simulator_definition do
    %Definition{
      form_value: "simulator",
      version: 1,
      provider_type: :simulator,
      client_key: :simulator_http,
      label: "Ground Network Simulator",
      description:
        "Cadence simulator control plane for local scheduling, profile sync, and provider events.",
      module: SimulatorHTTP,
      account_defaults: %{
        "display_name" => "Ground Network Simulator",
        "allowed_services" => "telemetry, tracking",
        "allowed_directions" => "downlink, uplink",
        "allowed_stations" => "",
        "max_quota" => ""
      },
      configuration: %ConfigurationDefinition{
        id: "provider-connector-configuration",
        description:
          "The connector describes control-plane fields; Cadence retains credential and mission-grant ownership.",
        sections: [
          %SectionDefinition{
            id: "provider-account-control-plane-section",
            number: "02",
            title: "Control Plane",
            fields: [
              %FieldDefinition{
                field: :base_url,
                label: "Provider API Base URL",
                type: :url,
                required: true,
                default: "http://127.0.0.1:4101",
                placeholder: "http://127.0.0.1:4101"
              },
              %FieldDefinition{
                field: :region_ref,
                label: "Region",
                type: :text,
                default: "local",
                placeholder: "local"
              },
              %FieldDefinition{
                field: :environment_ref,
                label: "Provider Environment",
                type: :text,
                required: true,
                default: "local-demo",
                placeholder: "local-demo"
              },
              %FieldDefinition{
                field: :event_ingestion_mode,
                label: "Event Ingestion",
                type: :select,
                required: true,
                default: "polling",
                options: [
                  {"Polling", "polling"},
                  {"Polling + webhook", "hybrid"},
                  {"Disabled", "disabled"}
                ]
              }
            ]
          }
        ]
      }
    }
  end
end
