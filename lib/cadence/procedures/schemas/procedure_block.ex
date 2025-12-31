defmodule Cadence.Procedures.ProcedureBlock do
  @moduledoc """
  A block within a procedure step.

  Blocks are the atomic units of procedure content. Each block has a type
  that determines its behavior and UI rendering. Blocks fall into categories:

  ## Content Blocks (display only)

  - `:text` - Rich markdown text
  - `:note` - Info callout
  - `:caution` - Yellow warning callout
  - `:warning` - Red critical warning callout
  - `:reference` - Link to external document

  ## Data Collection Blocks

  - `:text_input` - Free text entry
  - `:number_input` - Numeric with validation
  - `:select_input` - Dropdown/radio selection
  - `:checkbox_input` - Boolean or multi-select
  - `:timestamp_input` - Date/time capture
  - `:duration_input` - Time duration
  - `:attachment_input` - File upload
  - `:signature_input` - Operator signature

  ## Telemetry Blocks

  - `:telemetry_value` - Display current value
  - `:telemetry_check` - Auto-validate against criteria
  - `:telemetry_wait` - Wait for condition

  ## Command Blocks

  - `:command` - Send a single command
  - `:command_sequence` - Send multiple commands in order

  ## Reference Blocks

  - `:input_reference` - Display value from earlier input
  - `:variable_display` - Display procedure variable

  ## Subprocess Blocks

  - `:procedure_call` - Execute child procedure

  ## Content Format

  The `content` field is a map whose structure depends on block type.
  See individual type documentation for content schemas.

  ### Telemetry Value Content

      %{
        "item" => "target.EPS.battery_voltage",
        "format" => "%.2f",
        "unit" => "V",
        "source" => "cvt",  # optional: cvt, tsdb, api, manual
        "stale_threshold_seconds" => 30
      }

  ### Telemetry Check Content

      %{
        "item" => "target.EPS.battery_voltage",
        "pass_criteria" => ">= 24.0 and <= 32.0",
        "fail_action" => "block_signoff",  # warn, block_signoff, abort_procedure
        "auto_evaluate" => true
      }

  ### Command Content

      %{
        "command_name" => "SET_MODE",
        "target" => "execution_target",  # or "{{params.vehicle}}"
        "arguments" => %{"mode" => 1},
        "require_confirmation" => true,
        "verify_after" => %{
          "item" => "target.STATUS.current_mode",
          "expected" => 1,
          "timeout_seconds" => 10
        }
      }

  ### Number Input Content

      %{
        "min" => 0,
        "max" => 100,
        "step" => 0.1,
        "unit" => "V",
        "placeholder" => "Enter observed voltage",
        "pass_criteria" => ">= 24.0"
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Procedures.ProcedureStep

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @block_types [
    # Content blocks (display only)
    :text,
    :note,
    :caution,
    :warning,
    :reference,

    # Data collection blocks
    :text_input,
    :number_input,
    :select_input,
    :checkbox_input,
    :timestamp_input,
    :duration_input,
    :attachment_input,
    :signature_input,

    # Telemetry blocks
    :telemetry_value,
    :telemetry_check,
    :telemetry_wait,

    # Command blocks
    :command,
    :command_sequence,

    # Reference blocks
    :input_reference,
    :variable_display,

    # Subprocess
    :procedure_call
  ]

  @content_block_types [:text, :note, :caution, :warning, :reference]
  @input_block_types [
    :text_input,
    :number_input,
    :select_input,
    :checkbox_input,
    :timestamp_input,
    :duration_input,
    :attachment_input,
    :signature_input
  ]
  @telemetry_block_types [:telemetry_value, :telemetry_check, :telemetry_wait]
  @command_block_types [:command, :command_sequence]

  schema "procedure_blocks" do
    field :block_type, Ecto.Enum, values: @block_types
    field :position, :integer
    field :name, :string
    field :label, :string
    field :required, :boolean, default: false
    field :content, :map, default: %{}

    belongs_to :step, ProcedureStep

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:step_id, :block_type, :position]
  @optional_fields [:name, :label, :required, :content]

  @doc """
  Creates a changeset for a procedure block.
  """
  def changeset(block, attrs) do
    block
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, max: 100)
    |> validate_length(:label, max: 255)
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> validate_name_for_input_blocks()
    |> validate_content()
    |> foreign_key_constraint(:step_id)
  end

  @doc """
  Creates a changeset for updating block position.
  """
  def reposition_changeset(block, new_position) do
    block
    |> change()
    |> put_change(:position, new_position)
    |> validate_number(:position, greater_than_or_equal_to: 0)
  end

  # Input blocks should have names so they can be referenced
  defp validate_name_for_input_blocks(changeset) do
    block_type = get_field(changeset, :block_type)
    name = get_field(changeset, :name)

    if block_type in @input_block_types and (is_nil(name) or name == "") do
      add_error(changeset, :name, "is required for input blocks")
    else
      changeset
    end
  end

  defp validate_content(changeset) do
    block_type = get_field(changeset, :block_type)
    content = get_field(changeset, :content)

    case validate_content_for_type(block_type, content) do
      :ok -> changeset
      {:error, message} -> add_error(changeset, :content, message)
    end
  end

  defp validate_content_for_type(nil, _content), do: :ok
  defp validate_content_for_type(_type, nil), do: :ok

  defp validate_content_for_type(:text, content) do
    require_any_key(content, [:markdown, "markdown"], "text block requires 'markdown' field")
  end

  defp validate_content_for_type(type, content) when type in [:note, :caution, :warning] do
    require_any_key(content, [:text, "text"], "#{type} block requires 'text' field")
  end

  defp validate_content_for_type(:telemetry_value, content) do
    require_any_key(
      content,
      [:item, "item"],
      "telemetry_value block requires 'item' field"
    )
  end

  defp validate_content_for_type(:telemetry_check, content) do
    case require_any_key(
           content,
           [:item, "item"],
           "telemetry_check block requires 'item' field"
         ) do
      :ok ->
        case require_any_key(
               content,
               [:operator, "operator"],
               "telemetry_check block requires 'operator' field"
             ) do
          :ok ->
            require_any_key(
              content,
              [:expected, "expected"],
              "telemetry_check block requires 'expected' field"
            )

          {:error, _} = error ->
            error
        end

      {:error, _} = error ->
        error
    end
  end

  defp validate_content_for_type(:telemetry_wait, content) do
    case require_any_key(
           content,
           [:item, "item"],
           "telemetry_wait block requires 'item' field"
         ) do
      :ok ->
        case require_any_key(
               content,
               [:operator, "operator"],
               "telemetry_wait block requires 'operator' field"
             ) do
          :ok ->
            case require_any_key(
                   content,
                   [:expected, "expected"],
                   "telemetry_wait block requires 'expected' field"
                 ) do
              :ok ->
                require_any_key(
                  content,
                  [:timeout_ms, "timeout_ms"],
                  "telemetry_wait block requires 'timeout_ms' field"
                )

              {:error, _} = error ->
                error
            end

          {:error, _} = error ->
            error
        end

      {:error, _} = error ->
        error
    end
  end

  defp validate_content_for_type(:command, content) do
    require_any_key(
      content,
      [:command_name, "command_name"],
      "command block requires 'command_name' field"
    )
  end

  defp validate_content_for_type(:select_input, content) do
    require_any_key(content, [:options, "options"], "select_input block requires 'options' field")
  end

  defp validate_content_for_type(:procedure_call, content) do
    require_any_key(
      content,
      [:procedure_id, "procedure_id"],
      "procedure_call block requires 'procedure_id' field"
    )
  end

  defp validate_content_for_type(:input_reference, content) do
    case require_any_key(
           content,
           [:source_step, "source_step"],
           "input_reference block requires 'source_step' field"
         ) do
      :ok ->
        require_any_key(
          content,
          [:source_block, "source_block"],
          "input_reference block requires 'source_block' field"
        )

      {:error, _} = error ->
        error
    end
  end

  # Default: no specific validation
  defp validate_content_for_type(_type, _content), do: :ok

  defp require_any_key(content, keys, message) do
    if has_any_key?(content, keys) do
      :ok
    else
      {:error, message}
    end
  end

  defp has_any_key?(content, keys) when is_map(content) do
    Enum.any?(keys, &Map.has_key?(content, &1))
  end

  defp has_any_key?(_content, _keys), do: false

  # ─────────────────────────────────────────────────────────────
  # Type helpers
  # ─────────────────────────────────────────────────────────────

  @doc "Returns all valid block types."
  def block_types, do: @block_types

  @doc "Returns true if block type is a content/display block."
  def content_block?(%__MODULE__{block_type: type}), do: type in @content_block_types
  def content_block?(type) when is_atom(type), do: type in @content_block_types

  @doc "Returns true if block type collects user input."
  def input_block?(%__MODULE__{block_type: type}), do: type in @input_block_types
  def input_block?(type) when is_atom(type), do: type in @input_block_types

  @doc "Returns true if block type interacts with telemetry."
  def telemetry_block?(%__MODULE__{block_type: type}), do: type in @telemetry_block_types
  def telemetry_block?(type) when is_atom(type), do: type in @telemetry_block_types

  @doc "Returns true if block type sends commands."
  def command_block?(%__MODULE__{block_type: type}), do: type in @command_block_types
  def command_block?(type) when is_atom(type), do: type in @command_block_types

  @doc "Returns true if block type requires execution (not display-only)."
  def executable_block?(%__MODULE__{} = block) do
    input_block?(block) or telemetry_block?(block) or command_block?(block) or
      block.block_type == :procedure_call
  end
end
