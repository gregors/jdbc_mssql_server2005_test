class User < ActiveRecord::Base
  acts_as_paranoid

  acts_as_nested_set({:dependent => :destroy})

  attr_accessible :firstname, :lastname, :login, :email

end
