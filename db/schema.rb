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

ActiveRecord::Schema[8.0].define(version: 2026_03_21_110000) do
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
    t.index ["canonical_url"], name: "index_news_articles_on_canonical_url"
    t.index ["news_section_id"], name: "index_news_articles_on_news_section_id"
    t.index ["news_source_id", "content_hash"], name: "index_news_articles_on_news_source_id_and_content_hash", unique: true
    t.index ["news_source_id", "source_article_id"], name: "index_news_articles_on_news_source_id_and_source_article_id", unique: true, where: "(source_article_id IS NOT NULL)"
    t.index ["news_source_id"], name: "index_news_articles_on_news_source_id"
    t.index ["published_at"], name: "index_news_articles_on_published_at"
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
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["external_id"], name: "index_users_on_external_id"
    t.index ["tariff_id"], name: "index_users_on_tariff_id"
  end

  add_foreign_key "balance_ledger_entries", "payment_transactions"
  add_foreign_key "balance_ledger_entries", "users"
  add_foreign_key "news_articles", "news_sections"
  add_foreign_key "news_articles", "news_sources"
  add_foreign_key "news_crawl_runs", "news_sections"
  add_foreign_key "news_crawl_runs", "news_sources"
  add_foreign_key "news_sections", "news_sources"
  add_foreign_key "payment_transactions", "users"
  add_foreign_key "users", "tariffs"
end
