class Prompts::UsersController < ApplicationController
  def index
    @users = User.all

    if stale? etag: @users
      render layout: false
    end
  end
end
