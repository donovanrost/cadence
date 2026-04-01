defmodule Cadence.Domain.Accounts.Entities.User do
  @moduledoc """
  Pure domain entity representing a user in the system.

  Users are the primary actors in the system. They can be:
  - Regular organization members with roles (:owner, :admin, :member)
  - System administrators with platform-wide access

  This entity is persistence-agnostic and contains only business logic.

  ## Usage

      # Create a new user
      {:ok, user} = User.new(%{
        email: "user@example.com",
        organization_id: org_id
      })

      # Update email
      {:ok, user} = User.update_email(user, "new@example.com")

      # Check if user is confirmed
      User.confirmed?(user)
  """

  alias Cadence.Domain.Accounts.ValueObjects.UserRole
  alias Cadence.Time, as: CadenceTime

  @type t :: %__MODULE__{
          id: String.t() | nil,
          email: String.t(),
          hashed_password: String.t() | nil,
          confirmed_at: DateTime.t() | nil,
          role: UserRole.t(),
          system_admin: boolean(),
          organization_id: String.t() | nil,
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @enforce_keys [:email]
  defstruct [
    :id,
    :email,
    :hashed_password,
    :confirmed_at,
    :organization_id,
    :created_at,
    :updated_at,
    role: :member,
    system_admin: false
  ]

  @email_regex ~r/^[^@,;\s]+@[^@,;\s]+$/
  @email_max_length 160
  @password_min_length 12
  @password_max_length 72

  # ===========================================================================
  # Construction
  # ===========================================================================

  @doc """
  Creates a new user entity.

  ## Attributes

  Required:
  - `:email` - Valid email address

  Conditionally Required:
  - `:organization_id` - Required unless `:system_admin` is true

  Optional:
  - `:role` - User role (defaults to :member)
  - `:system_admin` - Whether this is a system admin (defaults to false)
  - `:hashed_password` - Pre-hashed password (if already hashed)

  ## Examples

      {:ok, user} = User.new(%{
        email: "user@example.com",
        organization_id: "org-123"
      })
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) do
    with {:ok, email} <- validate_email(attrs[:email]),
         {:ok, role} <- validate_role(attrs),
         {:ok, system_admin} <- validate_system_admin(attrs),
         :ok <- validate_organization_requirement(attrs, system_admin) do
      user = %__MODULE__{
        id: attrs[:id],
        email: email,
        hashed_password: attrs[:hashed_password],
        confirmed_at: attrs[:confirmed_at],
        role: role,
        system_admin: system_admin,
        organization_id: attrs[:organization_id],
        created_at: attrs[:created_at] || CadenceTime.now(),
        updated_at: attrs[:updated_at] || CadenceTime.now()
      }

      {:ok, user}
    end
  end

  @doc """
  Reconstructs a user entity from persisted data.

  Unlike `new/1`, this does not run validations as the data
  is assumed to be valid from the database.
  """
  @spec from_persistence(map()) :: t()
  def from_persistence(attrs) do
    %__MODULE__{
      id: attrs[:id],
      email: attrs[:email],
      hashed_password: attrs[:hashed_password],
      confirmed_at: attrs[:confirmed_at],
      role: parse_role(attrs[:role]),
      system_admin: attrs[:system_admin] || false,
      organization_id: attrs[:organization_id],
      created_at: attrs[:created_at],
      updated_at: attrs[:updated_at]
    }
  end

  # ===========================================================================
  # Email Operations
  # ===========================================================================

  @doc """
  Updates the user's email address.

  Returns an error if the new email is the same as the current email.
  """
  @spec update_email(t(), String.t()) :: {:ok, t()} | {:error, term()}
  def update_email(%__MODULE__{email: current} = user, new_email) do
    with {:ok, validated_email} <- validate_email(new_email),
         :ok <- ensure_email_changed(current, validated_email) do
      {:ok, %{user | email: validated_email, updated_at: CadenceTime.now()}}
    end
  end

  @doc """
  Confirms the user's email address.
  """
  @spec confirm(t()) :: {:ok, t()}
  def confirm(%__MODULE__{} = user) do
    now = CadenceTime.now() |> DateTime.truncate(:second)
    {:ok, %{user | confirmed_at: now, updated_at: now}}
  end

  # ===========================================================================
  # Password Operations
  # ===========================================================================

  @doc """
  Validates a plain-text password meets requirements.

  This does NOT hash the password - that should be done by the
  password hasher port before saving.
  """
  @spec validate_password(String.t()) :: :ok | {:error, term()}
  def validate_password(password) when is_binary(password) do
    cond do
      String.length(password) < @password_min_length ->
        {:error, :password_too_short}

      byte_size(password) > @password_max_length ->
        {:error, :password_too_long}

      true ->
        :ok
    end
  end

  def validate_password(_), do: {:error, :invalid_password}

  @doc """
  Sets the hashed password on the user.

  The password should already be hashed by the password hasher port.
  """
  @spec set_hashed_password(t(), String.t()) :: {:ok, t()}
  def set_hashed_password(%__MODULE__{} = user, hashed_password) do
    {:ok, %{user | hashed_password: hashed_password, updated_at: CadenceTime.now()}}
  end

  # ===========================================================================
  # Role Operations
  # ===========================================================================

  @doc """
  Updates the user's role within their organization.
  """
  @spec update_role(t(), UserRole.t()) :: {:ok, t()} | {:error, term()}
  def update_role(%__MODULE__{} = user, new_role) do
    case UserRole.validate(new_role) do
      {:ok, validated_role} ->
        {:ok, %{user | role: validated_role, updated_at: CadenceTime.now()}}

      error ->
        error
    end
  end

  @doc """
  Promotes the user to system admin status.
  """
  @spec make_system_admin(t()) :: {:ok, t()}
  def make_system_admin(%__MODULE__{} = user) do
    {:ok, %{user | system_admin: true, updated_at: CadenceTime.now()}}
  end

  @doc """
  Removes system admin status from the user.
  """
  @spec revoke_system_admin(t()) :: {:ok, t()}
  def revoke_system_admin(%__MODULE__{} = user) do
    {:ok, %{user | system_admin: false, updated_at: CadenceTime.now()}}
  end

  # ===========================================================================
  # Predicates
  # ===========================================================================

  @doc """
  Checks if the user's email is confirmed.
  """
  @spec confirmed?(t()) :: boolean()
  def confirmed?(%__MODULE__{confirmed_at: nil}), do: false
  def confirmed?(%__MODULE__{confirmed_at: _}), do: true

  @doc """
  Checks if the user is a system administrator.
  """
  @spec system_admin?(t()) :: boolean()
  def system_admin?(%__MODULE__{system_admin: true}), do: true
  def system_admin?(%__MODULE__{}), do: false

  @doc """
  Checks if the user has at least the specified role.
  """
  @spec has_role_at_least?(t(), UserRole.t()) :: boolean()
  def has_role_at_least?(%__MODULE__{system_admin: true}, _role), do: true

  def has_role_at_least?(%__MODULE__{role: role}, required_role) do
    UserRole.at_least?(role, required_role)
  end

  @doc """
  Checks if the user is an owner of their organization.
  """
  @spec owner?(t()) :: boolean()
  def owner?(%__MODULE__{role: :owner}), do: true
  def owner?(%__MODULE__{}), do: false

  @doc """
  Checks if the user is an admin or higher.
  """
  @spec admin_or_higher?(t()) :: boolean()
  def admin_or_higher?(%__MODULE__{system_admin: true}), do: true
  def admin_or_higher?(%__MODULE__{role: role}), do: UserRole.at_least?(role, :admin)

  @doc """
  Checks if the user has a password set.
  """
  @spec has_password?(t()) :: boolean()
  def has_password?(%__MODULE__{hashed_password: nil}), do: false
  def has_password?(%__MODULE__{hashed_password: hp}) when is_binary(hp), do: true
  def has_password?(%__MODULE__{}), do: false

  # ===========================================================================
  # Private Validation Helpers
  # ===========================================================================

  defp validate_email(nil), do: {:error, :email_required}
  defp validate_email(""), do: {:error, :email_required}

  defp validate_email(email) when is_binary(email) do
    email = String.trim(email) |> String.downcase()

    cond do
      String.length(email) > @email_max_length ->
        {:error, :email_too_long}

      not Regex.match?(@email_regex, email) ->
        {:error, :invalid_email_format}

      true ->
        {:ok, email}
    end
  end

  defp validate_email(_), do: {:error, :invalid_email}

  defp validate_role(%{role: role}) when is_atom(role), do: UserRole.validate(role)
  defp validate_role(%{role: role}) when is_binary(role), do: UserRole.validate(role)
  defp validate_role(_), do: {:ok, UserRole.default()}

  defp validate_system_admin(%{system_admin: true}), do: {:ok, true}
  defp validate_system_admin(_), do: {:ok, false}

  defp validate_organization_requirement(_attrs, true = _system_admin), do: :ok

  defp validate_organization_requirement(%{organization_id: org_id}, _system_admin)
       when is_binary(org_id) and org_id != "",
       do: :ok

  defp validate_organization_requirement(_, _), do: {:error, :organization_id_required}

  defp ensure_email_changed(current, new) when current == new do
    {:error, :email_not_changed}
  end

  defp ensure_email_changed(_, _), do: :ok

  defp parse_role(role) when is_atom(role), do: role

  defp parse_role(role) when is_binary(role) do
    case UserRole.parse(role) do
      {:ok, parsed} -> parsed
      :error -> :member
    end
  end

  defp parse_role(_), do: :member
end
