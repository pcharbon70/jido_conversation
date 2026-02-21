defmodule TerminalChat.UI.Root do
  @moduledoc """
  TermUI root component for the terminal chat example.
  """

  use TermUI.Elm

  alias TermUI.Command
  alias TermUI.Event
  alias TermUI.Renderer.Style
  alias TerminalChat.Session

  @max_input_chars 2_000
  @max_visible_lines 20

  @impl true
  def init(_opts) do
    %{
      input: "",
      status: startup_status(),
      history: Session.history()
    }
  end

  @impl true
  def event_to_msg(%Event.Key{key: :enter}, _state), do: {:msg, :submit}
  def event_to_msg(%Event.Key{key: :backspace}, _state), do: {:msg, :backspace}

  def event_to_msg(%Event.Key{key: "c", modifiers: modifiers}, _state) do
    if :ctrl in modifiers do
      {:msg, :quit}
    else
      {:msg, {:append, "c"}}
    end
  end

  def event_to_msg(%Event.Key{key: key}, _state) when is_binary(key), do: {:msg, {:append, key}}
  def event_to_msg(%Event.Paste{content: content}, _state), do: {:msg, {:append, content}}
  def event_to_msg(_event, _state), do: :ignore

  @impl true
  def update(:backspace, state) do
    {%{state | input: remove_last_grapheme(state.input)}, []}
  end

  def update({:append, content}, state) do
    input =
      (state.input <> content)
      |> String.slice(0, @max_input_chars)

    {%{state | input: input}, []}
  end

  def update(:quit, state) do
    {state, [Command.quit()]}
  end

  def update(:submit, state) do
    input = String.trim(state.input)

    cond do
      input == "" ->
        {%{state | input: ""}, []}

      input == "/quit" ->
        {%{state | input: ""}, [Command.quit()]}

      input == "/cancel" ->
        Session.cancel(self())
        {%{state | input: "", status: "Cancel requested..."}, []}

      String.starts_with?(input, "/search") ->
        query =
          input
          |> String.replace_prefix("/search", "")
          |> String.trim()

        Session.search(query, self())
        {%{state | input: "", status: "Search request submitted..."}, []}

      true ->
        Session.submit_message(input, self())
        {%{state | input: "", status: "Message submitted..."}, []}
    end
  end

  def update(_msg, state), do: {state, []}

  def handle_info({:terminal_chat, :history_changed}, state) do
    %{state | history: Session.history()}
  end

  def handle_info({:terminal_chat, {:status, text}}, state) when is_binary(text) do
    %{state | status: text}
  end

  def handle_info(_message, state), do: state

  @impl true
  def view(state) do
    stack(:vertical, [
      text("Terminal Chat (LLM + Search)", header_style()),
      text("Commands: /search <query> | /cancel | /quit (or Ctrl+C)", hint_style()),
      text("Status: #{state.status}", status_style(state.status)),
      text("", nil),
      text("Conversation", section_style()),
      text("------------", section_style()),
      stack(:vertical, history_nodes(state.history), width: :auto),
      text("", nil),
      text("> " <> state.input, input_style())
    ])
  end

  defp history_nodes(history) do
    history
    |> render_lines()
    |> case do
      [] ->
        [text("(no messages yet)", hint_style())]

      lines ->
        Enum.map(lines, fn {line, style} -> text(line, style) end)
    end
  end

  defp render_lines(history) do
    history
    |> Enum.flat_map(&message_to_lines/1)
    |> Enum.take(-@max_visible_lines)
  end

  defp message_to_lines(%{role: role, content: content, at: at}) do
    role_label = role_label(role)
    style = role_style(role)
    timestamp = format_time(at)
    lines = String.split(content, "\n", trim: true)

    case lines do
      [] ->
        [{"[#{timestamp}] #{role_label}: ", style}]

      [first | rest] ->
        first_line = "[#{timestamp}] #{role_label}: #{truncate_line(first)}"

        continued =
          Enum.map(rest, fn line ->
            {"  #{truncate_line(line)}", style}
          end)

        [{first_line, style} | continued]
    end
  end

  defp role_label(:user), do: "you"
  defp role_label(:assistant), do: "assistant"
  defp role_label(:tool), do: "tool"
  defp role_label(:system), do: "system"

  defp role_style(:user), do: Style.new(fg: :green)
  defp role_style(:assistant), do: Style.new(fg: :white)
  defp role_style(:tool), do: Style.new(fg: :yellow)
  defp role_style(:system), do: Style.new(fg: :bright_black)

  defp format_time(%DateTime{} = datetime) do
    datetime
    |> DateTime.to_time()
    |> Time.truncate(:second)
    |> Time.to_iso8601()
  end

  defp format_time(_), do: "00:00:00"

  defp truncate_line(line, max_length \\ 130) do
    if String.length(line) <= max_length do
      line
    else
      String.slice(line, 0, max_length - 3) <> "..."
    end
  end

  defp remove_last_grapheme(""), do: ""

  defp remove_last_grapheme(content) do
    content
    |> String.graphemes()
    |> Enum.drop(-1)
    |> Enum.join()
  end

  defp startup_status do
    if anthropic_key_present?() do
      "Ready."
    else
      "Ready. ANTHROPIC_API_KEY not set; chat uses fallback errors."
    end
  end

  defp anthropic_key_present? do
    case System.get_env("ANTHROPIC_API_KEY") || System.get_env("ANTROPIC_API_KEY") do
      value when is_binary(value) and value != "" -> true
      _ -> false
    end
  end

  defp header_style, do: Style.new(fg: :cyan, attrs: [:bold])
  defp hint_style, do: Style.new(fg: :bright_black)
  defp section_style, do: Style.new(fg: :bright_blue, attrs: [:bold])
  defp input_style, do: Style.new(fg: :bright_green, attrs: [:bold])

  defp status_style(status) when is_binary(status) do
    cond do
      String.contains?(status, "failed") -> Style.new(fg: :red, attrs: [:bold])
      String.contains?(status, "Cancel") -> Style.new(fg: :yellow)
      true -> Style.new(fg: :bright_cyan)
    end
  end
end
