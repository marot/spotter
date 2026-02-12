defmodule Spotter.Services.LlmCredentialsTest do
  use ExUnit.Case, async: false

  alias Spotter.Services.LlmCredentials

  setup do
    prev_app = Application.get_env(:langchain, :anthropic_key)
    prev_env = System.get_env("ANTHROPIC_API_KEY")

    on_exit(fn ->
      if prev_app,
        do: Application.put_env(:langchain, :anthropic_key, prev_app),
        else: Application.delete_env(:langchain, :anthropic_key)

      if prev_env,
        do: System.put_env("ANTHROPIC_API_KEY", prev_env),
        else: System.delete_env("ANTHROPIC_API_KEY")
    end)

    # Start each test with a clean slate
    Application.delete_env(:langchain, :anthropic_key)
    System.delete_env("ANTHROPIC_API_KEY")

    :ok
  end

  describe "anthropic_api_key/0 resolution order" do
    test "returns app config key when set" do
      Application.put_env(:langchain, :anthropic_key, "from-app-config")
      System.put_env("ANTHROPIC_API_KEY", "from-env")

      assert {:ok, "from-app-config"} = LlmCredentials.anthropic_api_key()
    end

    test "falls back to system env when app config is nil" do
      Application.delete_env(:langchain, :anthropic_key)
      System.put_env("ANTHROPIC_API_KEY", "from-env")

      assert {:ok, "from-env"} = LlmCredentials.anthropic_api_key()
    end

    test "falls back to system env when app config is empty" do
      Application.put_env(:langchain, :anthropic_key, "")
      System.put_env("ANTHROPIC_API_KEY", "from-env")

      assert {:ok, "from-env"} = LlmCredentials.anthropic_api_key()
    end
  end

  describe "anthropic_api_key/0 normalization" do
    test "returns error when both sources are nil" do
      assert {:error, :missing_api_key} = LlmCredentials.anthropic_api_key()
    end

    test "returns error when app config is empty string" do
      Application.put_env(:langchain, :anthropic_key, "")
      assert {:error, :missing_api_key} = LlmCredentials.anthropic_api_key()
    end

    test "returns error when app config is whitespace-only" do
      Application.put_env(:langchain, :anthropic_key, "   ")
      assert {:error, :missing_api_key} = LlmCredentials.anthropic_api_key()
    end

    test "returns error when env is empty string" do
      System.put_env("ANTHROPIC_API_KEY", "")
      assert {:error, :missing_api_key} = LlmCredentials.anthropic_api_key()
    end

    test "returns error when env is whitespace-only" do
      System.put_env("ANTHROPIC_API_KEY", "   ")
      assert {:error, :missing_api_key} = LlmCredentials.anthropic_api_key()
    end

    test "returns ok for non-blank key" do
      Application.put_env(:langchain, :anthropic_key, "sk-ant-test")
      assert {:ok, "sk-ant-test"} = LlmCredentials.anthropic_api_key()
    end
  end
end
