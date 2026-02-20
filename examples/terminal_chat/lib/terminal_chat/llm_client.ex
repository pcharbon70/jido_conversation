defmodule TerminalChat.LLMClient do
  @moduledoc """
  Minimal OpenAI-compatible chat client.
  """

  @endpoint "https://api.openai.com/v1/chat/completions"
  @default_model "gpt-4o-mini"
  @max_history_messages 20

  @type chat_message :: %{role: atom(), content: String.t()}

  @spec chat([chat_message()]) ::
          {:ok, %{content: String.t(), model: String.t()}}
          | {:error, term()}
  def chat(history) when is_list(history) do
    with {:ok, api_key} <- fetch_api_key(),
         {:ok, response} <- do_request(api_key, build_messages(history)) do
      {:ok, response}
    end
  end

  @spec summarize_search([chat_message()], String.t(), String.t()) ::
          {:ok, %{content: String.t(), model: String.t()}}
          | {:error, term()}
  def summarize_search(history, query, search_results)
      when is_list(history) and is_binary(query) and is_binary(search_results) do
    prompt = """
    Web search query: #{query}

    Search results:
    #{search_results}

    Provide a concise answer using the results above.
    If the results are uncertain, say so explicitly.
    """

    history = history ++ [%{role: :user, content: prompt}]
    chat(history)
  end

  defp fetch_api_key do
    case System.get_env("OPENAI_API_KEY") do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, :missing_openai_api_key}
    end
  end

  defp do_request(api_key, messages) do
    model = System.get_env("OPENAI_MODEL") || @default_model

    payload = %{
      model: model,
      messages: messages,
      temperature: 0.2
    }

    request_opts = [
      url: @endpoint,
      json: payload,
      headers: [{"authorization", "Bearer #{api_key}"}],
      connect_options: [timeout: 10_000],
      receive_timeout: 60_000,
      retry: false
    ]

    with {:ok, %Req.Response{status: status, body: body}} <- Req.post(request_opts),
         :ok <- validate_status(status, body),
         {:ok, content} <- extract_content(body) do
      {:ok, %{content: content, model: model}}
    else
      {:error, reason} ->
        {:error, reason}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, status, body}}
    end
  end

  defp validate_status(status, _body) when status in 200..299, do: :ok

  defp validate_status(status, body) do
    message =
      get_in(body, ["error", "message"]) ||
        "request failed with status #{status}"

    {:error, {:http_error, status, message}}
  end

  defp extract_content(%{"choices" => [choice | _]}) when is_map(choice) do
    choice
    |> Map.get("message", %{})
    |> Map.get("content")
    |> normalize_content()
  end

  defp extract_content(body), do: {:error, {:unexpected_response, body}}

  defp normalize_content(content) when is_binary(content) do
    content = String.trim(content)

    if content == "" do
      {:error, :empty_content}
    else
      {:ok, content}
    end
  end

  defp normalize_content(content) when is_list(content) do
    text =
      content
      |> Enum.map(&part_to_text/1)
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join("\n")
      |> String.trim()

    if text == "" do
      {:error, :empty_content}
    else
      {:ok, text}
    end
  end

  defp normalize_content(_content), do: {:error, :empty_content}

  defp part_to_text(%{"text" => text}) when is_binary(text), do: text
  defp part_to_text(%{"type" => "text", "text" => text}) when is_binary(text), do: text
  defp part_to_text(text) when is_binary(text), do: text
  defp part_to_text(_), do: nil

  defp build_messages(history) do
    system_prompt = %{
      role: "system",
      content: "You are a concise assistant in a terminal chat. Answer directly and clearly."
    }

    history
    |> Enum.take(-@max_history_messages)
    |> Enum.map(&to_openai_message/1)
    |> then(&[system_prompt | &1])
  end

  defp to_openai_message(%{role: :user, content: content}), do: %{role: "user", content: content}

  defp to_openai_message(%{role: :assistant, content: content}),
    do: %{role: "assistant", content: content}

  defp to_openai_message(%{role: :system, content: content}),
    do: %{role: "system", content: content}

  defp to_openai_message(%{role: :tool, content: content}) do
    %{
      role: "user",
      content: "Tool output:\n#{content}"
    }
  end
end
