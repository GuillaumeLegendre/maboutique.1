class ContactController < ApplicationController
  before_filter :authenticate_user!
  before_filter :valid_subscription?, :except => :create
  layout "backoffice"

  def create
    params[:contact][:user_id] = current_user.id
    params[:contact][:phone] = "+33#{params[:contact][:phone][1..-1]}" if params[:contact][:phone][0] == '0'
    unless params[:contact][:day].empty? && params[:contact][:month].empty? && params[:contact][:year].empty?
      params[:contact][:birthday] = Date.parse( "%02d-%02d-#{params[:contact][:year]}" % [params[:contact][:day].to_i, params[:contact][:month].to_i] )
    end
    @c = Contact.create(contact_params)
    if @c.valid?
      redirect_to :back, {notice: "Votre contact à bien été enregistré."}
    else
      errors = "
      <div id='error_explanation'>
      <h2> #{ActionController::Base.helpers.pluralize(@c.errors.length, "erreur")} ont empéché ce contact d'être enregistré :</h2>
      <ul>"
        @c.errors.full_messages.each do |msg|
          errors += "<li>#{msg}</li>"
        end
      errors += "
      </ul>
      </div>"

      redirect_to :back, notice: errors
    end
  end

  def new_email
    if params[:template] =~ /^[0-9]+$/
      @template = current_user.templates.where(id: params[:template]).first
    end
  end

  def send_email
    @contacts = Contact.where(user_id: current_user)
    @contacts = @contacts.where(gender: Contact.genders[params[:email][:gender]]) if params[:email][:gender].present?
    @contacts = @contacts.where(vip: params[:email][:vip]) if params[:email][:vip].present?
    @contacts.each do |c|
      ContactMailer.send_to_contact(c, params[:email], current_user).deliver
    end
    redirect_to :back, {notice: "Votre email va être envoyé."}
  end

  def save_template
    params[:template][:user_id] = current_user.id

    @t = Template.create(template_params)
    if @t.valid?
      render json: true
    else
      render json: @t.errors
    end
  end

  def edit_template
    params[:template][:user_id] = current_user.id
    @t = current_user.templates.where(id: params[:template_id]).first

    @t.update_attributes(template_params) if @t
    if @t.valid?
      render json: true
    else
      render json: @t.errors
    end
  end

  def new_sms
  end

  def send_sms
    sms_body = params[:sms][:body]
    @contacts = contacts_send_sms params[:sms][:gender], params[:sms][:vip]
    credits_by_sms = 1 # actually limit by type sms # sms_body.length/160+1
    if credits_by_sms * @contacts.length > current_user.credits
      return redirect_to :back, {alert: "Vous n'avez pas assez de crédits."}
    end
    resp = RestClient.post 'http://www.octopush-dm.com/api/sms', {
      user_login: 'quicksite.contact@gmail.com',
      api_key: 'faQ8nzpwbndTeYpImkjE52gi4jBKq58I',
      sms_recipients: @contacts.collect { |x| x.phone}.join(","),
      sms_text: params[:sms][:body],
      sms_type: 'XXX',
      request_mode: 'simu'#TODO remove
    }
    h = Hash.from_xml(resp)

    if h["octopush"]["error_code"] == "000" && h["octopush"]["failures"].nil?
      use_credits_sms h, credits_by_sms
      redirect_to :back, {notice: "Vos sms ont été envoyé."}
    elsif h["octopush"]["error_code"] == "000"
      use_credits_sms h, credits_by_sms
      h["octopush"]["failures"]
      puts h["octopush"] #TODO
      redirect_to :back, {notice: "#{h["octopush"]["number_of_sendings"]} sms ont été envoyé."} #TODO
    else
      puts h["octopush"]
      redirect_to :back, {notice: "Une erreur c'est produite vos sms n'ont pas été envoyé vos crédits n'ont pas été débité."}
    end
  end

  def upload_img
    u = current_user
    img = Image.new
    img.picture = params[:file]
    u.images << img

    render json: img.picture.url.to_json
  end

  def preview_number_send_sms
    @contacts = contacts_send_sms params[:gender], params[:vip]
    render json: @contacts.length
  end

  private
  def contact_params
    params.require(:contact).permit(:email, :last_name, :first_name, :birthday, :phone, :vip, :user_id, :gender)
  end

  def template_params
    params.require(:template).permit(:subject, :body, :user_id, :template_id)
  end

  def valid_subscription?
    if Date.today >= current_user.end_subscription
      # return redirect_to contact_payement_path, {notice: "Votre abonnement à expiré. Veuiller vous réabonner."}
    end
  end

  private
  def contacts_send_sms gender = nil, vip = nil
    @contacts = Contact.where(user_id: current_user).where.not('phone' => '')
    @contacts = @contacts.where(gender: Contact.genders[gender]) if gender.present?
    @contacts = @contacts.where(vip: vip) if vip.present?
    return @contacts
  end

  def use_credits_sms h, credits_by_sms
    current_credits = current_user.credits
    credits_use = h["octopush"]["number_of_sendings"].length * credits_by_sms
    new_credits = current_credits - credits_use
    current_user.update_attributes(credits: new_credits)
    new_credits
  end
end
