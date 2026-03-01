defmodule Jido.Conversation.Mode.Error do
  @moduledoc """
  Canonical mode API error taxonomy.
  """

  @type t ::
          {:unsupported_mode, atom(), [atom()]}
          | {:invalid_mode, term()}
          | {:invalid_mode_config, atom(), [map()]}
          | {:invalid_transition, atom(), atom()}
          | :run_in_progress
          | :run_not_found
          | :resume_not_allowed

  @type metadata :: %{
          required(:code) => atom(),
          required(:message) => String.t(),
          optional(:mode) => atom(),
          optional(:supported_modes) => [atom()],
          optional(:diagnostics) => [map()],
          optional(:from_status) => atom(),
          optional(:to_status) => atom()
        }

  @spec metadata(t()) :: metadata()
  def metadata({:unsupported_mode, mode, supported_modes}) do
    %{
      code: :unsupported_mode,
      message: "unsupported conversation mode",
      mode: mode,
      supported_modes: supported_modes
    }
  end

  def metadata({:invalid_mode, _mode}) do
    %{code: :invalid_mode, message: "invalid mode identifier"}
  end

  def metadata({:invalid_mode_config, mode, diagnostics}) do
    %{
      code: :invalid_mode_config,
      message: "invalid mode configuration",
      mode: mode,
      diagnostics: diagnostics
    }
  end

  def metadata({:invalid_transition, from_status, to_status}) do
    %{
      code: :invalid_transition,
      message: "invalid mode run transition",
      from_status: from_status,
      to_status: to_status
    }
  end

  def metadata(:run_in_progress) do
    %{code: :run_in_progress, message: "mode run already in progress"}
  end

  def metadata(:run_not_found) do
    %{code: :run_not_found, message: "mode run not found"}
  end

  def metadata(:resume_not_allowed) do
    %{code: :resume_not_allowed, message: "mode run cannot be resumed from current state"}
  end
end
