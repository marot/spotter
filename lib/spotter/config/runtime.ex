defmodule Spotter.Config.Runtime do
  @moduledoc """
  Resolves effective configuration values with deterministic precedence.

  Each accessor returns `{value, source}` where source indicates
  where the value came from (`:db`, `:toml`, `:env`, or `:default`).
  """

  alias Spotter.Config.Setting
  alias Spotter.Services.LlmCredentials

  require Ash.Query

  @default_transcripts_dir "~/.claude/projects"
  @default_summary_model "claude-3-5-haiku-latest"
  @default_summary_budget 4000

  @doc """
  Returns the effective transcripts directory.

  Precedence: DB override -> TOML `priv/spotter.toml` -> default `~/.claude/projects`.
  The `~` is expanded to the user's home directory.
  """
  @spec transcripts_dir() :: {String.t(), atom()}
  def transcripts_dir do
    case db_get("transcripts_dir") do
      {:ok, val} -> {expand_path(val), :db}
      :miss -> transcripts_dir_from_toml()
    end
  end

  @doc """
  Returns the effective summary model name.

  Precedence: DB override -> env `SPOTTER_SUMMARY_MODEL` -> default.
  """
  @spec summary_model() :: {String.t(), atom()}
  def summary_model do
    case db_get("summary_model") do
      {:ok, val} -> {val, :db}
      :miss -> summary_model_from_env()
    end
  end

  @doc """
  Returns the effective summary token budget.

  Precedence: DB override -> env `SPOTTER_SUMMARY_TOKEN_BUDGET` -> default.
  """
  @spec summary_token_budget() :: {pos_integer(), atom()}
  def summary_token_budget do
    case db_get("summary_token_budget") do
      {:ok, val} -> {parse_positive_integer(val, @default_summary_budget), :db}
      :miss -> summary_token_budget_from_env()
    end
  end

  @doc """
  Returns whether an Anthropic API key is configured.
  """
  @spec anthropic_key_present?() :: boolean()
  def anthropic_key_present? do
    match?({:ok, _}, LlmCredentials.anthropic_api_key())
  end

  # -- Private helpers --

  defp db_get(key) do
    case Setting
         |> Ash.Query.filter(key == ^key)
         |> Ash.read_one() do
      {:ok, %Setting{value: val}} -> {:ok, val}
      _ -> :miss
    end
  end

  defp transcripts_dir_from_toml do
    case read_toml_transcripts_dir() do
      {:ok, dir} -> {expand_path(dir), :toml}
      :error -> {expand_path(@default_transcripts_dir), :default}
    end
  end

  defp read_toml_transcripts_dir do
    path = Application.app_dir(:spotter, "priv/spotter.toml")

    with {:ok, content} <- File.read(path),
         {:ok, toml} <- Toml.decode(content),
         %{"transcripts_dir" => dir} when is_binary(dir) <- toml do
      {:ok, dir}
    else
      _ -> :error
    end
  end

  defp summary_model_from_env do
    case System.get_env("SPOTTER_SUMMARY_MODEL") do
      nil -> {@default_summary_model, :default}
      "" -> {@default_summary_model, :default}
      val -> {val, :env}
    end
  end

  defp summary_token_budget_from_env do
    case System.get_env("SPOTTER_SUMMARY_TOKEN_BUDGET") do
      nil -> {@default_summary_budget, :default}
      "" -> {@default_summary_budget, :default}
      val -> {parse_positive_integer(val, @default_summary_budget), :env}
    end
  end

  defp parse_positive_integer(val, fallback) when is_binary(val) do
    case Integer.parse(String.trim(val)) do
      {int, ""} when int > 0 -> int
      _ -> fallback
    end
  end

  defp expand_path(path) do
    String.replace(path, "~", System.user_home!())
  end
end
