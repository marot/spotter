defmodule Spotter.Transcripts.SessionsIndexTest do
  use ExUnit.Case, async: true

  alias Spotter.Transcripts.SessionsIndex

  @fixtures_dir Path.join(System.tmp_dir!(), "sessions_index_test_#{:rand.uniform(100_000)}")

  setup do
    File.mkdir_p!(@fixtures_dir)
    on_exit(fn -> File.rm_rf!(@fixtures_dir) end)
    %{dir: @fixtures_dir}
  end

  describe "read/1" do
    test "returns empty map when sessions-index.json is missing", %{dir: dir} do
      assert SessionsIndex.read(dir) == %{}
    end

    test "returns empty map for malformed JSON", %{dir: dir} do
      File.write!(Path.join(dir, "sessions-index.json"), "not json{{{")
      assert SessionsIndex.read(dir) == %{}
    end

    test "returns empty map for unexpected structure", %{dir: dir} do
      File.write!(Path.join(dir, "sessions-index.json"), Jason.encode!(%{"foo" => "bar"}))
      assert SessionsIndex.read(dir) == %{}
    end

    test "parses valid entries", %{dir: dir} do
      index = %{
        "version" => 1,
        "entries" => [
          %{
            "sessionId" => "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
            "customTitle" => "My Session",
            "summary" => "Did some work",
            "firstPrompt" => "Help me fix this",
            "created" => "2026-01-15T10:00:00.000Z",
            "modified" => "2026-01-15T11:30:00.000Z"
          }
        ]
      }

      File.write!(Path.join(dir, "sessions-index.json"), Jason.encode!(index))

      result = SessionsIndex.read(dir)
      assert map_size(result) == 1

      meta = result["aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"]
      assert meta.custom_title == "My Session"
      assert meta.summary == "Did some work"
      assert meta.first_prompt == "Help me fix this"
      assert %DateTime{} = meta.source_created_at
      assert %DateTime{} = meta.source_modified_at
    end

    test "normalizes blank strings to nil", %{dir: dir} do
      index = %{
        "version" => 1,
        "entries" => [
          %{
            "sessionId" => "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
            "customTitle" => "",
            "summary" => "   ",
            "firstPrompt" => nil
          }
        ]
      }

      File.write!(Path.join(dir, "sessions-index.json"), Jason.encode!(index))

      result = SessionsIndex.read(dir)
      meta = result["aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"]
      assert meta.custom_title == nil
      assert meta.summary == nil
      assert meta.first_prompt == nil
    end

    test "handles entries with missing optional fields", %{dir: dir} do
      index = %{
        "version" => 1,
        "entries" => [
          %{"sessionId" => "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"}
        ]
      }

      File.write!(Path.join(dir, "sessions-index.json"), Jason.encode!(index))

      result = SessionsIndex.read(dir)
      meta = result["aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"]
      assert meta.custom_title == nil
      assert meta.summary == nil
      assert meta.first_prompt == nil
      assert meta.source_created_at == nil
      assert meta.source_modified_at == nil
    end
  end
end
