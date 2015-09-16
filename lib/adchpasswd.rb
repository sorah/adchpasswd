require "adchpasswd/version"
require 'adchpasswd/app'

module Adchpasswd
  def self.app(*args)
    App.rack(*args)
  end
end
