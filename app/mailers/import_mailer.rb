class ImportMailer < ApplicationMailer
  def completed(identity, account)
    @account = account
    @landing_url = landing_url(script_name: account.slug)
    mail to: identity.email_address, subject: "Your Fizzy account import is complete"
  end

  def failed(identity, account)
    @account = account
    mail to: identity.email_address, subject: "Your Fizzy account import failed"
  end
end
