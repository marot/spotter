defmodule Spotter.Transcripts.Commit do
  @moduledoc "A Git commit captured during a Claude Code session."

  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshJsonApi.Resource]

  sqlite do
    table "commits"
    repo Spotter.Repo
  end

  json_api do
    type "commit"
  end

  actions do
    defaults [:read, :destroy]

    update :update do
      primary? true

      accept [
        :parent_hashes,
        :git_branch,
        :subject,
        :body,
        :author_name,
        :author_email,
        :authored_at,
        :committed_at,
        :patch_id_stable,
        :changed_files,
        :hotspots_status,
        :hotspots_analyzed_at,
        :hotspots_error,
        :hotspots_version,
        :hotspots_metadata,
        :tests_status,
        :tests_analyzed_at,
        :tests_error,
        :tests_version,
        :tests_metadata
      ]
    end

    create :create do
      primary? true

      accept [
        :commit_hash,
        :parent_hashes,
        :git_branch,
        :subject,
        :body,
        :author_name,
        :author_email,
        :authored_at,
        :committed_at,
        :patch_id_stable,
        :changed_files
      ]

      upsert? true
      upsert_identity :unique_commit_hash
      upsert_fields []
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :commit_hash, :string, allow_nil?: false
    attribute :parent_hashes, {:array, :string}, allow_nil?: false, default: []
    attribute :git_branch, :string
    attribute :subject, :string
    attribute :body, :string
    attribute :author_name, :string
    attribute :author_email, :string
    attribute :authored_at, :utc_datetime_usec
    attribute :committed_at, :utc_datetime_usec
    attribute :patch_id_stable, :string
    attribute :changed_files, {:array, :string}, allow_nil?: false, default: []

    attribute :hotspots_status, :atom do
      allow_nil? false
      default :pending
      constraints one_of: [:pending, :ok, :error]
    end

    attribute :hotspots_analyzed_at, :utc_datetime_usec
    attribute :hotspots_error, :string
    attribute :hotspots_version, :integer, allow_nil?: false, default: 1

    attribute :hotspots_metadata, :map do
      allow_nil? false
      default %{}
    end

    attribute :tests_status, :atom do
      allow_nil? false
      default :pending
      constraints one_of: [:pending, :ok, :error]
    end

    attribute :tests_analyzed_at, :utc_datetime_usec
    attribute :tests_error, :string
    attribute :tests_version, :integer, allow_nil?: false, default: 1

    attribute :tests_metadata, :map do
      allow_nil? false
      default %{}
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_commit_hash, [:commit_hash]
  end
end
