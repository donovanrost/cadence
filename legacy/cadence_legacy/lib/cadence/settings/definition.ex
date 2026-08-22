defmodule Cadence.Settings.Definition do
  @moduledoc """
  Macro for defining settings with metadata for validation and UI rendering.

  Settings are defined in code, not in the database schema. This means adding
  new settings requires no migrations - just add a new `setting` declaration.

  ## Usage

      defmodule Cadence.Settings.Definitions.Procedures do
        use Cadence.Settings.Definition

        @namespace :procedures

        setting :required_approvals,
          type: :integer,
          default: 1,
          scope: :both,
          restrictiveness: :higher,
          validate: {:range, 1, 10},
          label: "Required Approvals",
          description: "Number of approvals needed"
      end

  ## Options

  - `:type` - The value type (`:integer`, `:boolean`, `:string`)
  - `:default` - Default value when no setting is stored
  - `:scope` - Where this setting can be set (`:org_only`, `:mission_only`, `:both`)
  - `:restrictiveness` - How mission overrides relate to org values
    - `:none` - No restriction on override
    - `:higher` - Mission value must be >= org value
    - `:lower` - Mission value must be <= org value
    - `:false_is_stricter` - false is more restrictive than true
  - `:validate` - Optional validation rule as a tuple (see below)
  - `:label` - Human-readable label for UI
  - `:description` - Longer description for UI

  ## Validation Rules

  Validation rules are specified as tuples:
  - `{:range, min, max}` - Value must be >= min and <= max
  - `{:min, value}` - Value must be >= value
  - `{:max, value}` - Value must be <= value
  - `{:one_of, list}` - Value must be one of the given values
  - `:any` or `nil` - No additional validation beyond type checking
  """

  @type validation_rule ::
          {:range, number(), number()}
          | {:min, number()}
          | {:max, number()}
          | {:one_of, list()}
          | :any
          | nil

  @type setting_definition :: %{
          key: atom(),
          type: :integer | :boolean | :string,
          default: any(),
          scope: :org_only | :mission_only | :both,
          restrictiveness: :none | :higher | :lower | :false_is_stricter,
          validate: validation_rule(),
          label: String.t(),
          description: String.t()
        }

  defmacro __using__(_opts) do
    quote do
      import Cadence.Settings.Definition, only: [setting: 2]
      Module.register_attribute(__MODULE__, :settings, accumulate: true)
      @before_compile Cadence.Settings.Definition
    end
  end

  defmacro setting(key, opts) do
    quote do
      @settings {unquote(key), unquote(opts)}
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      @doc """
      Returns all settings defined in this module as a list of {key, opts} tuples.
      """
      def __settings__, do: @settings |> Enum.reverse()

      @doc """
      Returns the namespace for this settings module.
      """
      def __namespace__, do: @namespace

      @doc """
      Returns a setting definition by key, or nil if not found.
      """
      def get_definition(key) do
        case Enum.find(__settings__(), fn {k, _opts} -> k == key end) do
          nil -> nil
          {_key, opts} -> build_definition(key, opts)
        end
      end

      @doc """
      Returns all setting definitions as maps.
      """
      def list_definitions do
        Enum.map(__settings__(), fn {key, opts} -> build_definition(key, opts) end)
      end

      defp build_definition(key, opts) do
        %{
          key: key,
          type: Keyword.fetch!(opts, :type),
          default: Keyword.fetch!(opts, :default),
          scope: Keyword.fetch!(opts, :scope),
          restrictiveness: Keyword.fetch!(opts, :restrictiveness),
          validate: Keyword.get(opts, :validate),
          label: Keyword.fetch!(opts, :label),
          description: Keyword.fetch!(opts, :description)
        }
      end
    end
  end

  @doc """
  Validates a value against a validation rule.
  """
  @spec valid?(any(), validation_rule()) :: boolean()
  def valid?(_value, nil), do: true
  def valid?(_value, :any), do: true

  def valid?(value, {:range, min, max}) when is_number(value) do
    value >= min and value <= max
  end

  def valid?(value, {:min, min}) when is_number(value), do: value >= min
  def valid?(value, {:max, max}) when is_number(value), do: value <= max
  def valid?(value, {:one_of, list}), do: value in list

  def valid?(_value, _rule), do: false
end
