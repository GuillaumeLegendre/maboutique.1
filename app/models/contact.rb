class Contact < ActiveRecord::Base
  enum gender: %w(male female)

  belongs_to :user

  validates :email, presence: true, email: true

  acts_as_birthday :birthday

  def self.send_birthday_mail
    contacts = Contact.birthday_today
    contacts.each do |c|
      if c.user.birthday_mail
        t = c.user.templates.where(birthday: true).first
        email = {subject: t.subject, body: t.body}
        ContactMailer.send_to_contact(c, email, c.user).deliver
      end
    end
  end
end
