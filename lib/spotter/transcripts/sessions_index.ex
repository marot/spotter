defmodule Spotter.Transcripts.SessionsIndex do
  @moduledoc """
  Reads Claude Code `sessions-index.json` files to extract resume metadata
  (custom title, summary, first prompt, timestamps) for session enrichment.
  """

  require Logger

  @doc """
  Reads a `sessions-index.json` from the given transcript directory.

  Returns a map of `%{session_id => metadata}` where metadata contains:
  - `:custom_title` - user-set session title (or nil)
  - `:summary` - auto-generated session summary (or nil)
  - `:first_prompt` - the first user prompt text (or nil)
  - `:source_created_at` - session creation timestamp (or nil)
  - `:source_modified_at` - session last-modified timestamp (or nil)

  Returns an empty map if the file is missing or malformed.
  """
  @spec read(String.t()) :: %{String.t() => map()}
  def read(dir) do
    path = Path.join(dir, "sessions-index.json")

    case File.read(path) do
      {:ok, content} ->
        parse(content, path)

      {:error, :enoent} ->
        %{}

      {:error, reason} ->
        Logger.warning("Cannot read #{path}: #{reason}")
        %{}
    end
  end

  defp parse(content, path) do
    case Jason.decode(content) do
      {:ok, %{"entries" => entries}} when is_list(entries) ->
        Map.new(entries, fn entry ->
          {entry["sessionId"], parse_entry(entry)}
        end)

      {:ok, _} ->
        Logger.warning("Unexpected sessions-index.json structure in #{path}")
        %{}

      {:error, reason} ->
        Logger.warning("Malformed JSON in #{path}: #{inspect(reason)}")
        %{}
    end
  end

  defp parse_entry(entry) do
    %{
      custom_title: normalize_blank(entry["customTitle"]),
      summary: normalize_blank(entry["summary"]),
      first_prompt: normalize_blank(entry["firstPrompt"]),
      source_created_at: parse_datetime(entry["created"]),
      source_modified_at: parse_datetime(entry["modified"])
    }
  end

  defp normalize_blank(nil), do: nil
  defp normalize_blank(""), do: nil

  defp normalize_blank(str) when is_binary(str) do
    case String.trim(str) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_blank(_), do: nil

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(_), do: nil
end
