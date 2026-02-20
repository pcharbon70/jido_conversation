# Terminal Chat Example

Standalone terminal conversation app built with `TermUI`.

Features:

- chat with an LLM (OpenAI-compatible endpoint)
- `/search <query>` web search tool call (Wikipedia API)
- `/cancel` to cancel any in-flight chat/search request
- `/quit` (or `Ctrl+C`) to exit

## Prerequisites

- Elixir 1.19+
- OTP 28+
- `OPENAI_API_KEY` set in your shell if you want LLM responses
- optional: `OPENAI_MODEL` (defaults to `gpt-4o-mini`)

## Run

```bash
cd examples/terminal_chat
mix deps.get
mix run run.exs
```

## Commands

- type plain text to send a chat prompt
- `/search latest elixir release`
- `/cancel`
- `/quit`
