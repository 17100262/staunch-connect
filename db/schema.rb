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

ActiveRecord::Schema[8.1].define(version: 2026_09_05_093156) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "ai_conversations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_ai_conversations_on_user_id"
  end

  create_table "ai_messages", force: :cascade do |t|
    t.bigint "ai_conversation_id", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.string "role", null: false
    t.jsonb "tool_calls", default: [], null: false
    t.datetime "updated_at", null: false
    t.index ["ai_conversation_id"], name: "index_ai_messages_on_ai_conversation_id"
  end

  create_table "connections", force: :cascade do |t|
    t.text "access_token"
    t.datetime "access_token_expires_at"
    t.datetime "created_at", null: false
    t.text "credential"
    t.string "last_error"
    t.datetime "last_used_at"
    t.string "source"
    t.string "status"
    t.datetime "updated_at", null: false
  end

  create_table "invoice_line_items", force: :cascade do |t|
    t.boolean "billable", default: true, null: false
    t.string "clickup_task_id"
    t.datetime "created_at", null: false
    t.decimal "estimate_hours", precision: 12, scale: 6
    t.decimal "hourly_rate", precision: 10, scale: 2
    t.bigint "invoice_id", null: false
    t.string "ticket"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["invoice_id"], name: "index_invoice_line_items_on_invoice_id"
  end

  create_table "invoices", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "month", null: false
    t.string "name"
    t.bigint "project_mapping_id", null: false
    t.datetime "updated_at", null: false
    t.index ["project_mapping_id", "month"], name: "index_invoices_on_project_mapping_id_and_month", unique: true
    t.index ["project_mapping_id"], name: "index_invoices_on_project_mapping_id"
  end

  create_table "project_mappings", force: :cascade do |t|
    t.string "clickup_space_id"
    t.string "clickup_space_name"
    t.datetime "created_at", null: false
    t.decimal "default_hourly_rate", precision: 10, scale: 2
    t.string "hubstaff_project_id"
    t.string "hubstaff_project_name"
    t.datetime "updated_at", null: false
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "ai_conversations", "users"
  add_foreign_key "ai_messages", "ai_conversations"
  add_foreign_key "invoice_line_items", "invoices"
  add_foreign_key "invoices", "project_mappings"
  add_foreign_key "sessions", "users"
end
