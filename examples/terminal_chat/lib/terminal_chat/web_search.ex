defmodule TerminalChat.WebSearch do
  @moduledoc """
  Minimal web search tool backed by Wikipedia's public search API.
  """

  @endpoint "https://en.wikipedia.org/w/api.php"

  @type result :: %{
          title: String.t(),
          snippet: String.t(),
          url: String.t()
        }

  @spec search(String.t()) :: {:ok, [result()]} | {:error, term()}
  def search(query) when is_binary(query) do
    query = String.trim(query)

    if query == "" do
      {:error, :empty_query}
    else
      do_search(query)
    end
  end

  @spec format_results([result()]) :: String.t()
  def format_results(results) when is_list(results) do
    results
    |> Enum.take(5)
    |> Enum.with_index(1)
    |> Enum.map(fn {result, index} ->
      "#{index}. #{result.title} - #{result.snippet} (#{result.url})"
    end)
    |> Enum.join("\n")
  end

  defp do_search(query) do
    opts = [
      url: @endpoint,
      params: [
        action: "query",
        list: "search",
        format: "json",
        utf8: 1,
        srlimit: 5,
        srsearch: query
      ],
      receive_timeout: 30_000,
      connect_options: [timeout: 10_000],
      retry: false
    ]

    with {:ok, %Req.Response{status: status, body: body}} <- Req.get(opts),
         :ok <- validate_status(status),
         {:ok, results} <- parse_results(body) do
      {:ok, results}
    else
      {:error, reason} -> {:error, reason}
      {:ok, %Req.Response{status: status}} -> {:error, {:http_error, status}}
    end
  end

  defp validate_status(status) when status in 200..299, do: :ok
  defp validate_status(status), do: {:error, {:http_error, status}}

  defp parse_results(%{"query" => %{"search" => rows}}) when is_list(rows) do
    results =
      rows
      |> Enum.map(&row_to_result/1)
      |> Enum.reject(&is_nil/1)

    if results == [] do
      {:error, :no_results}
    else
      {:ok, results}
    end
  end

  defp parse_results(body), do: {:error, {:unexpected_response, body}}

  defp row_to_result(%{"title" => title, "snippet" => snippet, "pageid" => pageid})
       when is_binary(title) and is_binary(snippet) and is_integer(pageid) do
    %{
      title: title,
      snippet: clean_snippet(snippet),
      url: "https://en.wikipedia.org/?curid=#{pageid}"
    }
  end

  defp row_to_result(_), do: nil

  defp clean_snippet(snippet) do
    snippet
    |> String.replace(~r/<[^>]*>/, "")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.trim()
  end
end
