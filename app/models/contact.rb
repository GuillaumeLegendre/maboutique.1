class Contact < ActiveRecord::Base
  belongs_to :user

  validates :email, presence: true, email: true
end
