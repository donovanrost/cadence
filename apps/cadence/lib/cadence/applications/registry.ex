defmodule Cadence.Applications.Registry do
  @moduledoc """
  Tolerant registry of compiled first-party product applications.

  Durable application and renderer identifiers remain strings. Registry lookup
  never converts operator-controlled input into atoms.
  """

  alias Cadence.Applications.{
    ApplicationDefinition,
    ResourceClaimDefinition,
    ResourceContract
  }

  alias Cadence.Applications.{
    OpsConsole,
    TelemetryDecom
  }

  @type fetch_error ::
          :unknown_application
          | :unsupported_application_version
          | :invalid_application_definition

  @spec all() :: [ApplicationDefinition.t()]
  def all, do: [TelemetryDecom.definition(), OpsConsole.definition(), cfdp()]

  @spec available() :: [ApplicationDefinition.t()]
  def available do
    Enum.filter(all(), fn definition ->
      ApplicationDefinition.available?(definition) and
        ApplicationDefinition.validate(definition) == :ok
    end)
  end

  @spec available_for_scope(ApplicationDefinition.scope()) :: [ApplicationDefinition.t()]
  def available_for_scope(scope) do
    Enum.filter(available(), &(scope in &1.installable_scopes))
  end

  @spec known_keys() :: [binary()]
  def known_keys, do: Enum.map(all(), & &1.application_key)

  @doc "Resolves platform access from a validated, available server-owned definition."
  @spec platform?(binary(), ApplicationDefinition.scope()) :: boolean()
  def platform?(application_key, scope) do
    case fetch_available(application_key) do
      {:ok, definition} -> ApplicationDefinition.platform?(definition, scope)
      {:error, _reason} -> false
    end
  end

  @spec fetch(binary(), pos_integer() | :latest | nil) ::
          {:ok, ApplicationDefinition.t()} | {:error, fetch_error()}
  def fetch(application_key, version \\ :latest)

  def fetch(application_key, version) when is_binary(application_key) do
    case Map.fetch(definitions(), application_key) do
      {:ok, %ApplicationDefinition{} = definition}
      when version in [:latest, nil, definition.version] ->
        case ApplicationDefinition.validate(definition) do
          :ok -> {:ok, definition}
          {:error, :invalid_application_definition} -> {:error, :invalid_application_definition}
        end

      {:ok, %ApplicationDefinition{}} ->
        {:error, :unsupported_application_version}

      :error ->
        {:error, :unknown_application}
    end
  end

  def fetch(_application_key, _version), do: {:error, :unknown_application}

  @spec fetch_available(binary(), pos_integer() | :latest | nil) ::
          {:ok, ApplicationDefinition.t()} | {:error, fetch_error() | :application_unavailable}
  def fetch_available(application_key, version \\ :latest) do
    with {:ok, definition} <- fetch(application_key, version),
         true <- ApplicationDefinition.available?(definition) do
      {:ok, definition}
    else
      false -> {:error, :application_unavailable}
      {:error, reason} -> {:error, reason}
    end
  end

  defp definitions do
    Map.new(all(), &{&1.application_key, &1})
  end

  defp cfdp do
    %ApplicationDefinition{
      application_key: "cfdp",
      version: 1,
      display_name: "CFDP",
      description: "Transfer files using the CCSDS File Delivery Protocol.",
      trust: :first_party,
      availability: :roadmap,
      installable_scopes: [:mission],
      configuration_contract: %{
        schema_id: "cadence.cfdp.configuration",
        version: 1
      },
      resource_contract: %ResourceContract{
        claims: [
          %ResourceClaimDefinition{
            claim_type: :source_endpoint,
            scope: :mission,
            mode: :reference,
            description: "Ingress and egress endpoints used by CFDP entities."
          },
          %ResourceClaimDefinition{
            claim_type: :transport,
            scope: :mission,
            mode: :reference,
            description: "Mission transports selected for CFDP protocol traffic."
          }
        ]
      },
      capability_contributions: [
        %{
          kind: :managed_application,
          family_key: :cfdp_receive,
          scope: :source_endpoint,
          maturity: :runtime_proof
        }
      ]
    }
  end
end
