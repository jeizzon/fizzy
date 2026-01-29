class ImportsController < ApplicationController
  disallow_account_scope only: %i[ new create ]

  layout "public"

  def new
  end

  def create
    signup = Signup.new(identity: Current.identity, full_name: "Import", skip_account_seeding: true)

    if signup.complete
      start_import(signup.account)
    else
      render :new, alert: "Couldn't create account."
    end
  end

  def show
    @import = Current.account.imports.find(params[:id])
  end

  private
    def start_import(account)
      import = nil

      Current.set(account: account) do
        import = account.imports.create!(identity: Current.identity, file: params[:file])
        import.process_later
      end

      redirect_to import_path(import, script_name: account.slug)
    end
end
