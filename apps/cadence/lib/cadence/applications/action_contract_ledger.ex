defmodule Cadence.Applications.ActionContractLedger do
  @moduledoc """
  Exact surface/action contract ledger for the non-Ops federated applications.

  Every row is the complete envelope identity:

      {application_key, application_version, surface_id, surface_version, action_id}

  The ledger compares the authoritative application definitions, the compiled
  provider bindings, and the central application registry. A request is
  admitted only when all three sources contain the exact same row.
  """

  alias Cadence.Applications.{ActionRequest, ApplicationDefinition, Registry}
  alias Cadence.Applications.{Comms, MissionCatalog, Spacecraft, TelemetryDecom}

  @type binding :: {binary(), pos_integer(), binary(), pos_integer(), binary()}

  @contributors [MissionCatalog, Spacecraft, TelemetryDecom, Comms]
  @optional_contributors [CadenceWeb.ApplicationContributions.OrganizationAdmin]
  @max_bindings 128

  @compile {:no_warn_undefined,
            {CadenceWeb.ApplicationContributions.OrganizationAdmin, :definition, 0}}
  @compile {:no_warn_undefined,
            {CadenceWeb.ApplicationContributions.OrganizationAdmin, :action_provider, 0}}

  @spec contributors() :: [module()]
  def contributors do
    @contributors ++ Enum.filter(@optional_contributors, &Code.ensure_loaded?/1)
  end

  @doc "Returns the rows declared by the authoritative application modules."
  @spec declared() :: [binding()]
  def declared do
    contributors()
    |> Enum.flat_map(fn contributor -> declared_bindings(contributor.definition()) end)
  end

  @doc "Returns the rows exposed by the compiled action providers."
  @spec provider() :: [binding()]
  def provider do
    contributors()
    |> Enum.flat_map(fn contributor -> provider_bindings(contributor) end)
  end

  @doc "Returns the rows currently contributed to the central application registry."
  @spec registry() :: [binding()]
  def registry do
    registry_definitions()
    |> Enum.flat_map(&declared_bindings/1)
  end

  @doc "Returns all three ordered ledgers for review and executable checks."
  @spec ledgers() :: %{declared: [binding()], provider: [binding()], registry: [binding()]}
  def ledgers do
    %{declared: declared(), provider: provider(), registry: registry()}
  end

  @doc "Validates exact equality, identity uniqueness, and registry authority."
  @spec validate() :: :ok | {:error, :invalid_application_action_contract_ledger}
  def validate do
    with true <- valid_contributors?(),
         true <- valid_registry_authority?(),
         %{declared: declared, provider: provider, registry: registry} <- ledgers(),
         true <- valid_bindings?(declared),
         true <- valid_bindings?(provider),
         true <- valid_bindings?(registry),
         true <- declared == provider,
         true <- declared == registry do
      :ok
    else
      _invalid -> {:error, :invalid_application_action_contract_ledger}
    end
  rescue
    _exception -> {:error, :invalid_application_action_contract_ledger}
  catch
    _kind, _value -> {:error, :invalid_application_action_contract_ledger}
  end

  @doc "Admits a request only when the provider and registry still match authority."
  @spec admit(ActionRequest.t(), module()) :: :ok | {:error, :unsupported_application_action}
  def admit(%ActionRequest{} = request, provider) when is_atom(provider) do
    with {:ok, contributor} <- contributor_for(request.application_key),
         {:ok, definition} <- registry_definition(contributor, request.application_version),
         true <- definition == contributor.definition(),
         {:ok, provider_rows} <- provider_bindings_result(contributor),
         true <- provider == contributor.action_provider(),
         true <- request_binding(request) in declared_bindings(definition),
         true <- request_binding(request) in provider_rows,
         true <- request_binding(request) in registry_bindings(definition) do
      :ok
    else
      _rejected -> {:error, :unsupported_application_action}
    end
  rescue
    _exception -> {:error, :unsupported_application_action}
  catch
    _kind, _value -> {:error, :unsupported_application_action}
  end

  @spec admit(ActionRequest.t()) :: :ok | {:error, :unsupported_application_action}
  def admit(%ActionRequest{} = request) do
    case contributor_for(request.application_key) do
      {:ok, contributor} -> admit(request, contributor.action_provider())
      :error -> {:error, :unsupported_application_action}
    end
  end

  def admit(_request), do: {:error, :unsupported_application_action}

  defp valid_contributors? do
    contributors = contributors()
    keys = Enum.map(contributors, &contributor_key/1)

    length(contributors) <= @max_bindings and
      Enum.all?(contributors, &valid_contributor?/1) and
      length(keys) == length(Enum.uniq(keys))
  end

  defp valid_contributor?(contributor) do
    Code.ensure_loaded?(contributor) and
      function_exported?(contributor, :definition, 0) and
      function_exported?(contributor, :action_provider, 0) and
      match?(%ApplicationDefinition{}, contributor.definition())
  end

  defp valid_registry_authority? do
    registry_definitions = Registry.all()
    keys = Enum.map(registry_definitions, & &1.application_key)

    Enum.all?(contributors(), fn contributor ->
      key = contributor_key(contributor)

      Enum.count(registry_definitions, &(&1.application_key == key)) == 1
    end) and
      length(keys) == length(Enum.uniq(keys))
  end

  defp registry_definitions do
    all = Registry.all()

    Enum.flat_map(contributors(), fn contributor ->
      key = contributor_key(contributor)
      Enum.filter(all, &(&1.application_key == key))
    end)
  end

  defp registry_definition(contributor, version) do
    case Enum.find(registry_definitions(), fn definition ->
           definition.application_key == contributor_key(contributor) and
             definition.version == version
         end) do
      %ApplicationDefinition{} = definition -> {:ok, definition}
      nil -> :error
    end
  end

  defp contributor_for(application_key) when is_binary(application_key) do
    case Enum.find(contributors(), &(contributor_key(&1) == application_key)) do
      nil -> :error
      contributor -> {:ok, contributor}
    end
  end

  defp contributor_for(_application_key), do: :error

  defp contributor_key(contributor), do: contributor.definition().application_key

  defp declared_bindings(%ApplicationDefinition{} = definition) do
    Enum.flat_map(definition.surfaces, fn surface ->
      Enum.map(surface.actions, fn action_id ->
        {definition.application_key, definition.version, surface.surface_id, surface.version,
         action_id}
      end)
    end)
  end

  defp declared_bindings(_definition), do: []

  defp registry_bindings(%ApplicationDefinition{} = definition),
    do: declared_bindings(definition)

  defp provider_bindings(contributor) do
    case provider_bindings_result(contributor) do
      {:ok, bindings} -> bindings
      :error -> []
    end
  end

  defp provider_bindings_result(contributor) do
    provider = contributor.action_provider()

    cond do
      not is_atom(provider) or not Code.ensure_loaded?(provider) ->
        :error

      function_exported?(provider, :surface_action_bindings, 0) ->
        normalize_provider_bindings(provider, provider.surface_action_bindings(), contributor)

      function_exported?(provider, :all, 0) ->
        normalize_provider_bindings(provider, provider.all(), contributor)

      true ->
        :error
    end
  rescue
    _exception -> :error
  catch
    _kind, _value -> :error
  end

  defp normalize_provider_bindings(provider, rows, contributor) when is_list(rows) do
    application_key = contributor_key(contributor)
    application_version = contributor.definition().version

    normalized =
      Enum.map(rows, fn
        {surface_id, surface_version, action_id} ->
          {application_key, application_version, surface_id, surface_version, action_id}

        %{surface_id: surface_id, version: surface_version, id: action_id} ->
          {application_key, application_version, surface_id, surface_version, action_id}

        _invalid ->
          nil
      end)

    if provider == contributor.action_provider() and Enum.all?(normalized, &valid_binding?/1),
      do: {:ok, normalized},
      else: :error
  end

  defp normalize_provider_bindings(_provider, _rows, _contributor), do: :error

  defp request_binding(%ActionRequest{
         application_key: application_key,
         application_version: application_version,
         surface_id: surface_id,
         surface_version: surface_version,
         action_id: action_id
       }),
       do: {application_key, application_version, surface_id, surface_version, action_id}

  defp valid_bindings?(bindings) when is_list(bindings) and length(bindings) <= @max_bindings do
    Enum.all?(bindings, &valid_binding?/1) and
      length(bindings) == length(Enum.uniq(bindings))
  end

  defp valid_bindings?(_bindings), do: false

  defp valid_binding?(
         {application_key, application_version, surface_id, surface_version, action_id}
       ) do
    is_binary(application_key) and application_key != "" and
      is_integer(application_version) and application_version > 0 and
      is_binary(surface_id) and surface_id != "" and
      is_integer(surface_version) and surface_version > 0 and
      is_binary(action_id) and action_id != ""
  end

  defp valid_binding?(_binding), do: false
end
