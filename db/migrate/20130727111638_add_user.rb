class AddUser < ActiveRecord::Migration
  def up
    create_table :users do |t|
      t.string   "login",                                       :limit => 100
      t.datetime "deleted_at"
      t.datetime "created_at"
      t.datetime "updated_at"
      t.integer  "lock_version",                                               :default => 0, :null => false
      t.string   "firstname",                                   :limit => 100
      t.string   "lastname",                                    :limit => 100
      t.string   "email",                                       :limit => 100
      t.integer  "lft"
      t.integer  "rgt"
      t.integer  "parent_id"
    end

    15.times{|i| User.create(:firstname => 'test', :lastname => "user#{i}")}
  end

  def down
    drop_table :users
  end
end
