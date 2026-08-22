defmodule Cadence.Applications.SurfaceDefinition do
  @moduledoc """
  Host-owned presentation contract contributed by a registered application.

  Surface definitions describe product purpose, data, refresh, and renderer
  identity. They do not contain arbitrary queries, modules, HEEx, or client code.
  """

  alias Cadence.Applications.ActionDefinition
  alias Cadence.Extensions.Presentation.ReferenceDefinition

  @type purpose ::
          :overview
          | :configuration
          | :preview
          | :operations
          | :collection
          | :subject_detail
          | :activity

  @type scope :: ActionDefinition.scope()
  @type placement :: :application_workspace | :ops_workspace | :ops_dock | :administration
  @type refresh ::
          :static
          | :after_action
          | {:poll, pos_integer()}
          | {:subscription, binary()}

  @type renderer ::
          {:generated_form, binary()}
          | {:declarative, binary()}
          | {:trusted, binary()}

  @type t :: %__MODULE__{
          surface_id: binary(),
          version: pos_integer(),
          purpose: purpose(),
          scope: scope(),
          placement: placement(),
          subject_contract: map() | nil,
          navigation: map(),
          data_contract: map(),
          references: %{optional(binary()) => ReferenceDefinition.t()},
          actions: [binary()],
          refresh: refresh(),
          renderer: renderer()
        }

  @enforce_keys [
    :surface_id,
    :version,
    :purpose,
    :scope,
    :placement,
    :data_contract,
    :renderer
  ]

  defstruct [
    :surface_id,
    :version,
    :purpose,
    :scope,
    :placement,
    :subject_contract,
    :renderer,
    navigation: %{},
    data_contract: %{},
    references: %{},
    actions: [],
    refresh: :static
  ]

  @purposes [
    :overview,
    :configuration,
    :preview,
    :operations,
    :collection,
    :subject_detail,
    :activity
  ]
  @scopes [:organization, :mission, :spacecraft, :source_endpoint, :transport]
  @placements [:application_workspace, :ops_workspace, :ops_dock, :administration]
  @max_references 32
  @max_actions 32

  @spec validate(t()) :: :ok | {:error, :invalid_application_surface_definition}
  def validate(%__MODULE__{} = surface) do
    with true <- valid_text?(surface.surface_id),
         true <- is_integer(surface.version) and surface.version > 0,
         true <- surface.purpose in @purposes,
         true <- surface.scope in @scopes,
         true <- surface.placement in @placements,
         true <- valid_subject_contract?(surface.subject_contract),
         true <- valid_navigation?(surface.navigation),
         true <- valid_data_contract?(surface.data_contract),
         true <- valid_references?(surface.references),
         true <- valid_actions?(surface.actions),
         true <- valid_refresh?(surface.refresh),
         true <- valid_renderer?(surface.renderer) do
      :ok
    else
      _invalid -> {:error, :invalid_application_surface_definition}
    end
  end

  def validate(_surface), do: {:error, :invalid_application_surface_definition}

  defp valid_subject_contract?(nil), do: true

  defp valid_subject_contract?(contract),
    do: valid_versioned_contract?(contract, :schema_id)

  defp valid_navigation?(navigation) when is_map(navigation) do
    Enum.all?(Map.keys(navigation), &(&1 in [:label, :order])) and
      optional_text?(Map.get(navigation, :label)) and
      optional_integer?(Map.get(navigation, :order))
  end

  defp valid_navigation?(_navigation), do: false

  defp valid_data_contract?(contract), do: valid_versioned_contract?(contract, :query_id)

  defp valid_versioned_contract?(contract, identity_key) when is_map(contract) do
    Enum.all?(Map.keys(contract), &(&1 in [identity_key, :version])) and
      valid_text?(Map.get(contract, identity_key)) and
      positive_integer?(Map.get(contract, :version))
  end

  defp valid_versioned_contract?(_contract, _identity_key), do: false

  defp valid_references?(references) when is_map(references) do
    map_size(references) <= @max_references and
      Enum.all?(references, fn
        {reference_id, %ReferenceDefinition{} = reference} ->
          valid_text?(reference_id) and ReferenceDefinition.validate(reference) == :ok

        _invalid ->
          false
      end)
  end

  defp valid_references?(_references), do: false

  defp valid_actions?(actions) when is_list(actions) do
    length(actions) <= @max_actions and Enum.all?(actions, &valid_text?/1) and
      length(Enum.uniq(actions)) == length(actions)
  end

  defp valid_actions?(_actions), do: false

  defp valid_refresh?(refresh) when refresh in [:static, :after_action], do: true
  defp valid_refresh?({:poll, interval}), do: positive_integer?(interval)
  defp valid_refresh?({:subscription, subscription_id}), do: valid_text?(subscription_id)
  defp valid_refresh?(_refresh), do: false

  defp valid_renderer?({kind, renderer_id})
       when kind in [:generated_form, :declarative, :trusted],
       do: valid_text?(renderer_id)

  defp valid_renderer?(_renderer), do: false

  defp positive_integer?(value), do: is_integer(value) and value > 0
  defp optional_integer?(nil), do: true
  defp optional_integer?(value), do: is_integer(value)
  defp valid_text?(value), do: is_binary(value) and value != ""
  defp optional_text?(nil), do: true
  defp optional_text?(value), do: is_binary(value)
end
