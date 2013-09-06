# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended to check this file into your version control system.

ActiveRecord::Schema.define(:version => 20130727111638) do

  create_table "users", :force => true do |t|
    t.string   "login",        :limit => 100
    t.datetime "deleted_at",   :limit => 23
    t.datetime "created_at",   :limit => 23
    t.datetime "updated_at",   :limit => 23
    t.integer  "lock_version", :limit => 4,   :default => 0, :null => false
    t.string   "firstname",    :limit => 100
    t.string   "lastname",     :limit => 100
    t.string   "email",        :limit => 100
    t.integer  "lft",          :limit => 4
    t.integer  "rgt",          :limit => 4
    t.integer  "parent_id",    :limit => 4
  end

end
