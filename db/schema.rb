# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_04_08_100000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "balance_ledger_entries", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "payment_transaction_id"
    t.integer "kind", null: false
    t.integer "amount_cents", null: false
    t.integer "balance_after_cents", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["payment_transaction_id"], name: "index_balance_ledger_entries_on_payment_transaction_id"
    t.index ["user_id"], name: "index_balance_ledger_entries_on_user_id"
  end

  create_table "games", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.string "normalized_name"
    t.string "external_game_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["external_game_id"], name: "index_games_on_external_game_id"
    t.index ["normalized_name"], name: "index_games_on_normalized_name"
    t.index ["slug"], name: "index_games_on_slug", unique: true
  end

  create_table "news_article_games", force: :cascade do |t|
    t.bigint "news_article_id", null: false
    t.bigint "game_id"
    t.string "request_id", null: false
    t.string "identified_game_name", null: false
    t.string "slug"
    t.decimal "confidence", precision: 5, scale: 4
    t.string "model"
    t.string "external_game_id"
    t.jsonb "raw_response", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["game_id"], name: "index_news_article_games_on_game_id"
    t.index ["news_article_id"], name: "index_news_article_games_on_news_article_id", unique: true
    t.index ["request_id"], name: "index_news_article_games_on_request_id"
    t.index ["slug"], name: "index_news_article_games_on_slug"
  end

  create_table "news_article_reads", force: :cascade do |t|
    t.bigint "news_article_id", null: false
    t.bigint "user_id"
    t.uuid "visitor_uuid"
    t.datetime "read_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["news_article_id", "user_id"], name: "index_news_article_reads_on_news_article_id_and_user_id", unique: true, where: "(user_id IS NOT NULL)"
    t.index ["news_article_id", "visitor_uuid"], name: "index_news_article_reads_on_news_article_id_and_visitor_uuid", unique: true, where: "(visitor_uuid IS NOT NULL)"
    t.index ["news_article_id"], name: "index_news_article_reads_on_news_article_id"
    t.index ["user_id", "read_at"], name: "index_news_article_reads_on_user_id_and_read_at"
    t.index ["user_id"], name: "index_news_article_reads_on_user_id"
    t.index ["visitor_uuid", "read_at"], name: "index_news_article_reads_on_visitor_uuid_and_read_at"
  end

  create_table "news_articles", force: :cascade do |t|
    t.bigint "news_source_id", null: false
    t.bigint "news_section_id", null: false
    t.string "source_article_id"
    t.string "canonical_url", null: false
    t.string "title"
    t.text "preview_text"
    t.text "body_text"
    t.string "image_url"
    t.datetime "published_at"
    t.datetime "fetched_at", null: false
    t.string "content_hash", null: false
    t.jsonb "raw_payload", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "body_html", default: "", null: false
    t.text "source_title"
    t.text "source_preview_text"
    t.text "source_body_text"
    t.datetime "translated_at"
    t.string "translation_model"
    t.string "translation_target_locale", default: "ru", null: false
    t.string "translation_source_locale", default: "en", null: false
    t.text "preview_html", default: "", null: false
    t.string "translation_status", default: "pending", null: false
    t.text "translation_error"
    t.datetime "translation_completed_at"
    t.datetime "translation_started_at"
    t.string "translation_request_id"
    t.integer "translation_attempts", default: 0, null: false
    t.bigint "news_crawl_run_id"
    t.index ["canonical_url"], name: "index_news_articles_on_canonical_url"
    t.index ["news_crawl_run_id"], name: "index_news_articles_on_news_crawl_run_id"
    t.index ["news_section_id"], name: "index_news_articles_on_news_section_id"
    t.index ["news_source_id", "content_hash"], name: "index_news_articles_on_news_source_id_and_content_hash", unique: true
    t.index ["news_source_id", "source_article_id"], name: "index_news_articles_on_news_source_id_and_source_article_id", unique: true, where: "(source_article_id IS NOT NULL)"
    t.index ["news_source_id"], name: "index_news_articles_on_news_source_id"
    t.index ["published_at"], name: "index_news_articles_on_published_at"
    t.index ["translation_request_id"], name: "index_news_articles_on_translation_request_id"
    t.index ["translation_status", "created_at"], name: "index_news_articles_on_translation_status_and_created_at"
    t.index ["translation_status", "translation_started_at"], name: "idx_on_translation_status_translation_started_at_76d70d1b51"
  end

  create_table "news_crawl_runs", force: :cascade do |t|
    t.bigint "news_source_id", null: false
    t.bigint "news_section_id"
    t.integer "status", default: 0, null: false
    t.datetime "started_at", null: false
    t.datetime "finished_at"
    t.integer "pages_visited", default: 0, null: false
    t.integer "articles_found", default: 0, null: false
    t.integer "articles_saved", default: 0, null: false
    t.integer "articles_skipped", default: 0, null: false
    t.jsonb "crawl_errors", default: [], null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["news_section_id"], name: "index_news_crawl_runs_on_news_section_id"
    t.index ["news_source_id", "status"], name: "index_news_crawl_runs_on_news_source_id_and_status"
    t.index ["news_source_id"], name: "index_news_crawl_runs_on_news_source_id"
    t.index ["started_at"], name: "index_news_crawl_runs_on_started_at"
  end

  create_table "news_game_bookmarks", force: :cascade do |t|
    t.bigint "game_id", null: false
    t.bigint "user_id"
    t.uuid "visitor_uuid"
    t.datetime "bookmarked_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["game_id", "user_id"], name: "index_news_game_bookmarks_on_game_id_and_user_id", unique: true, where: "(user_id IS NOT NULL)"
    t.index ["game_id", "visitor_uuid"], name: "index_news_game_bookmarks_on_game_id_and_visitor_uuid", unique: true, where: "(visitor_uuid IS NOT NULL)"
    t.index ["game_id"], name: "index_news_game_bookmarks_on_game_id"
    t.index ["user_id", "bookmarked_at"], name: "index_news_game_bookmarks_on_user_id_and_bookmarked_at"
    t.index ["visitor_uuid", "bookmarked_at"], name: "index_news_game_bookmarks_on_visitor_uuid_and_bookmarked_at"
  end

  create_table "news_sections", force: :cascade do |t|
    t.bigint "news_source_id", null: false
    t.string "name", null: false
    t.string "url", null: false
    t.boolean "active", default: true, null: false
    t.jsonb "config", default: {}, null: false
    t.datetime "last_crawled_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["news_source_id", "name"], name: "index_news_sections_on_news_source_id_and_name", unique: true
    t.index ["news_source_id"], name: "index_news_sections_on_news_source_id"
  end

  create_table "news_sources", force: :cascade do |t|
    t.string "name", null: false
    t.string "base_url", null: false
    t.boolean "active", default: true, null: false
    t.integer "crawl_delay_min_seconds", default: 1, null: false
    t.integer "crawl_delay_max_seconds", default: 3, null: false
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_news_sources_on_name", unique: true
  end

  create_table "payment_transactions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "provider", default: "yoomoney", null: false
    t.string "payment_method", default: "bank_card", null: false
    t.string "label", null: false
    t.integer "status", default: 0, null: false
    t.integer "requested_amount_cents", null: false
    t.integer "credited_amount_cents", default: 0, null: false
    t.integer "provider_net_amount_cents", default: 0, null: false
    t.string "provider_operation_id"
    t.datetime "paid_at"
    t.jsonb "provider_payload", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["label"], name: "index_payment_transactions_on_label", unique: true
    t.index ["provider_operation_id"], name: "index_payment_transactions_on_provider_operation_id"
    t.index ["user_id"], name: "index_payment_transactions_on_user_id"
  end

  create_table "shards", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "game_id", null: false
    t.string "name", null: false
    t.string "world_seed", null: false
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["game_id"], name: "index_shards_on_game_id"
    t.index ["status"], name: "index_shards_on_status"
    t.index ["user_id", "game_id"], name: "index_shards_on_user_id_and_game_id", unique: true
    t.index ["user_id"], name: "index_shards_on_user_id"
  end

  create_table "tariffs", force: :cascade do |t|
    t.string "name", null: false
    t.integer "monthly_price_cents", default: 0, null: false
    t.integer "hourly_rate_cents", default: 0, null: false
    t.integer "billing_period_days", default: 30, null: false
    t.boolean "active", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_tariffs_on_name", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "password_digest", null: false
    t.integer "role", default: 2, null: false
    t.integer "balance_cents", default: 0, null: false
    t.integer "hourly_rate_cents", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.string "external_id"
    t.jsonb "import_metadata", default: {}, null: false
    t.datetime "last_hourly_charge_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "tariff_id"
    t.string "prime_time_zone", default: "UTC", null: false
    t.integer "prime_slots_utc", default: [], null: false, array: true
    t.string "nickname", null: false
    t.boolean "nickname_change_used", default: false, null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["external_id"], name: "index_users_on_external_id"
    t.index ["nickname"], name: "index_users_on_nickname", unique: true
    t.index ["prime_slots_utc"], name: "index_users_on_prime_slots_utc", using: :gin
    t.index ["tariff_id"], name: "index_users_on_tariff_id"
  end

  add_foreign_key "balance_ledger_entries", "payment_transactions"
  add_foreign_key "balance_ledger_entries", "users"
  add_foreign_key "news_article_games", "games"
  add_foreign_key "news_article_games", "news_articles"
  add_foreign_key "news_article_reads", "news_articles"
  add_foreign_key "news_article_reads", "users"
  add_foreign_key "news_articles", "news_crawl_runs"
  add_foreign_key "news_articles", "news_sections"
  add_foreign_key "news_articles", "news_sources"
  add_foreign_key "news_crawl_runs", "news_sections"
  add_foreign_key "news_crawl_runs", "news_sources"
  add_foreign_key "news_game_bookmarks", "games"
  add_foreign_key "news_game_bookmarks", "users"
  add_foreign_key "news_sections", "news_sources"
  add_foreign_key "payment_transactions", "users"
  add_foreign_key "shards", "games"
  add_foreign_key "shards", "users"
  add_foreign_key "users", "tariffs"
end
