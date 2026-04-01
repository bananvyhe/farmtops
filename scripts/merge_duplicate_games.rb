#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "../config/environment"

class MergeDuplicateGames
  Result = Struct.new(
    :groups_seen,
    :duplicates_found,
    :games_merged,
    :article_game_rows_reassigned,
    :bookmarks_reassigned,
    :bookmarks_deleted,
    :games_deleted,
    keyword_init: true
  )

  def initialize(logger: Rails.logger)
    @logger = logger
  end

  def call(dry_run: false)
    result = Result.new(
      groups_seen: 0,
      duplicates_found: 0,
      games_merged: 0,
      article_game_rows_reassigned: 0,
      bookmarks_reassigned: 0,
      bookmarks_deleted: 0,
      games_deleted: 0
    )

    duplicate_groups.each do |group|
      result.groups_seen += 1
      canonical = canonical_game(group)
      duplicates = group.reject { |game| game.id == canonical.id }
      next if duplicates.empty?

      result.duplicates_found += duplicates.length
      logger.info("[MergeDuplicateGames] canonical=#{game_debug(canonical)} duplicates=#{duplicates.map { |game| game_debug(game) }.join(",")}")

      next if dry_run

      ActiveRecord::Base.transaction do
        duplicates.each do |duplicate|
          result.article_game_rows_reassigned += NewsArticleGame.where(game_id: duplicate.id).update_all(game_id: canonical.id)
          result.bookmarks_reassigned += reassign_bookmarks!(duplicate, canonical, result)
          duplicate.destroy!
          result.games_deleted += 1
          result.games_merged += 1
        end
      end
    end

    result
  end

  private

  attr_reader :logger

  def duplicate_groups
    scope = Game.order(:created_at, :id)
    groups = []

    groups.concat(grouped_games(scope.where.not(external_game_id: nil), "external_game_id"))
    groups.concat(grouped_games(scope.where.not(normalized_name: [nil, ""]), "normalized_name"))
    groups.concat(grouped_games(scope.where("normalized_name IS NULL OR normalized_name = ''"), "name_ci"))

    groups.uniq { |group| group.map(&:id).sort.join(":") }
  end

  def grouped_games(scope, key)
    case key
    when "external_game_id"
      scope.group_by { |game| game.external_game_id.to_s.strip.downcase.presence }.values.select { |games| games.length > 1 }
    when "normalized_name"
      scope.group_by { |game| game.normalized_name.to_s.strip.downcase.presence }.values.select { |games| games.length > 1 }
    else
      scope.group_by { |game| game.name.to_s.strip.downcase.presence }.values.select { |games| games.length > 1 }
    end
  end

  def canonical_game(group)
    group.min_by { |game| [game.created_at || Time.at(0), game.id] }
  end

  def reassign_bookmarks!(duplicate, canonical, result)
    migrated = 0
    NewsGameBookmark.where(game_id: duplicate.id).find_each do |bookmark|
      existing = NewsGameBookmark.find_by(game_id: canonical.id, user_id: bookmark.user_id, visitor_uuid: bookmark.visitor_uuid)
      if existing.present?
        existing.update!(bookmarked_at: [existing.bookmarked_at, bookmark.bookmarked_at].compact.max)
        bookmark.destroy!
        result.bookmarks_deleted += 1
      else
        bookmark.update!(game_id: canonical.id)
        migrated += 1
      end
    end
    migrated
  end

  def game_debug(game)
    "#{game.id}:#{game.slug}:#{game.name}"
  end
end

dry_run = ENV.fetch("DRY_RUN", "1") != "0"
result = MergeDuplicateGames.new.call(dry_run: dry_run)

puts JSON.pretty_generate(
  dry_run: dry_run,
  groups_seen: result.groups_seen,
  duplicates_found: result.duplicates_found,
  games_merged: result.games_merged,
  article_game_rows_reassigned: result.article_game_rows_reassigned,
  bookmarks_reassigned: result.bookmarks_reassigned,
  bookmarks_deleted: result.bookmarks_deleted,
  games_deleted: result.games_deleted
)
