defmodule JidoConversation.ConversationRef do
  @moduledoc """
  Canonical project-scoped conversation identity helpers.

  Subject format:
  `project/<url-encoded-project-id>/conversation/<url-encoded-conversation-id>`
  """

  @enforce_keys [:project_id, :conversation_id, :subject]
  defstruct [:project_id, :conversation_id, :subject]

  @typedoc """
  Parsed project-scoped conversation reference.
  """
  @type t :: %__MODULE__{
          project_id: String.t(),
          conversation_id: String.t(),
          subject: String.t()
        }

  @type error ::
          {:invalid_project_id, term()}
          | {:invalid_conversation_id, term()}
          | {:invalid_subject, term()}

  @subject_prefix "project/"
  @subject_separator "/conversation/"

  @doc """
  Builds a canonical project-scoped conversation reference.
  """
  @spec new(String.t(), String.t()) :: {:ok, t()} | {:error, error()}
  def new(project_id, conversation_id) do
    with :ok <- validate_id(project_id, :project_id),
         :ok <- validate_id(conversation_id, :conversation_id) do
      {:ok,
       %__MODULE__{
         project_id: project_id,
         conversation_id: conversation_id,
         subject: compose_subject(project_id, conversation_id)
       }}
    end
  end

  @doc """
  Same as `new/2`, but raises on invalid input.
  """
  @spec new!(String.t(), String.t()) :: t() | no_return()
  def new!(project_id, conversation_id) do
    case new(project_id, conversation_id) do
      {:ok, ref} ->
        ref

      {:error, reason} ->
        raise ArgumentError,
              "invalid conversation ref project_id=#{inspect(project_id)} " <>
                "conversation_id=#{inspect(conversation_id)} reason=#{inspect(reason)}"
    end
  end

  @doc """
  Returns the canonical project-scoped subject for ids.
  """
  @spec subject(String.t(), String.t()) :: String.t()
  def subject(project_id, conversation_id) do
    new!(project_id, conversation_id).subject
  end

  @doc """
  Parses a canonical project-scoped subject into ids.
  """
  @spec parse_subject(String.t()) :: {:ok, t()} | {:error, error()}
  def parse_subject(subject) when is_binary(subject) do
    with true <-
           String.starts_with?(subject, @subject_prefix) or {:error, {:invalid_subject, subject}},
         body <- String.replace_prefix(subject, @subject_prefix, ""),
         [encoded_project_id, encoded_conversation_id] <-
           String.split(body, @subject_separator, parts: 2),
         project_id <- URI.decode_www_form(encoded_project_id),
         conversation_id <- URI.decode_www_form(encoded_conversation_id),
         :ok <- validate_id(project_id, :project_id),
         :ok <- validate_id(conversation_id, :conversation_id) do
      {:ok,
       %__MODULE__{
         project_id: project_id,
         conversation_id: conversation_id,
         subject: subject
       }}
    else
      _ -> {:error, {:invalid_subject, subject}}
    end
  end

  def parse_subject(subject), do: {:error, {:invalid_subject, subject}}

  defp compose_subject(project_id, conversation_id) do
    "#{@subject_prefix}#{URI.encode_www_form(project_id)}#{@subject_separator}" <>
      URI.encode_www_form(conversation_id)
  end

  defp validate_id(value, field) when is_binary(value) do
    if String.trim(value) == "" do
      {:error, {:"invalid_#{field}", value}}
    else
      :ok
    end
  end

  defp validate_id(value, field), do: {:error, {:"invalid_#{field}", value}}
end
