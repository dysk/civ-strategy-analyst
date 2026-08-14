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

ActiveRecord::Schema[8.1].define(version: 2026_08_14_165715) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "analyses", force: :cascade do |t|
    t.decimal "cost_usd", precision: 10, scale: 6
    t.datetime "created_at", null: false
    t.jsonb "digest", default: {}, null: false
    t.bigint "game_id", null: false
    t.integer "input_tokens"
    t.string "model", null: false
    t.integer "output_tokens"
    t.text "prompt"
    t.text "report", null: false
    t.datetime "updated_at", null: false
    t.index ["game_id"], name: "index_analyses_on_game_id"
  end

  create_table "game_events", force: :cascade do |t|
    t.string "civ"
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.bigint "game_id", null: false
    t.jsonb "payload", default: {}, null: false
    t.integer "seq", null: false
    t.integer "session_index", null: false
    t.integer "turn", null: false
    t.datetime "updated_at", null: false
    t.index ["game_id", "civ"], name: "index_game_events_on_game_id_and_civ"
    t.index ["game_id", "event_type"], name: "index_game_events_on_game_id_and_event_type"
    t.index ["game_id", "turn"], name: "index_game_events_on_game_id_and_turn"
    t.index ["game_id"], name: "index_game_events_on_game_id"
  end

  create_table "games", force: :cascade do |t|
    t.boolean "completed", default: false, null: false
    t.datetime "created_at", null: false
    t.string "game_speed"
    t.string "map_script"
    t.string "map_size"
    t.integer "max_turns"
    t.string "name"
    t.string "start_era"
    t.datetime "updated_at", null: false
    t.string "victory_type"
    t.string "winner_civ"
  end

  create_table "players", force: :cascade do |t|
    t.string "civ", null: false
    t.datetime "created_at", null: false
    t.bigint "game_id", null: false
    t.string "handicap"
    t.boolean "human", default: false, null: false
    t.string "leader_name"
    t.datetime "updated_at", null: false
    t.index ["game_id"], name: "index_players_on_game_id"
  end

  add_foreign_key "analyses", "games"
  add_foreign_key "game_events", "games"
  add_foreign_key "players", "games"
end
