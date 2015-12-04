require 'sinatra/base'
require 'net/ldap'
require 'tilt/erb'

module Adchpasswd
  class App < Sinatra::Base
    CONTEXT_RACK_ENV_NAME = 'adchpasswd.ctx'
    set :root, File.expand_path(File.join(__dir__, '..', '..', 'app'))

    def self.initialize_context(config)
      {}.tap do |ctx|
        ctx[:config] = config
      end
    end

    def self.rack(config={})
      klass = self

      context = initialize_context(config)
      app = lambda { |env|
        env[CONTEXT_RACK_ENV_NAME] = context
        klass.call(env)
      }
    end

    configure do
      enable :logging
    end

    helpers do
      def context
        request.env[CONTEXT_RACK_ENV_NAME]
      end

      def ldap_arg
        context[:config][:ldap]
      end

      def default_upn_suffix
        context[:config][:default_upn_suffix]
      end


      def encode_unicodepwd(password)
        # https://msdn.microsoft.com/en-us/library/cc223248.aspx
        ["\"#{password}\"".encode('utf-16le').each_char.map(&:ord).pack('S<*')]
      end

      def escape_for_filter(str)
        #http://social.technet.microsoft.com/wiki/contents/articles/5312.active-directory-characters-to-escape.aspx
        str.
          gsub(?*, "\\2A").
          gsub(?(, "\\28").
          gsub(?), "\\29").
          gsub("\\", "\\5C").
          gsub(?\0, "\\00")
      end

      def log(*args)
        if request.env['rack.logger']
          request.env['rack.logger'].info(*args)
        end
      end

      def bind(login, password)
        is_upn = login.include?('@')
        is_dn = login.include?('=')

        case
        when is_upn
          binddn = login
        when is_dn
          binddn = login
        else
          # https://msdn.microsoft.com/en-us/library/cc223499.aspx
          binddn = "#{login}@#{default_upn_suffix}"
        end

        ldap = Net::LDAP.new(ldap_arg) 

        log "bind with #{binddn}"

        unless ldap.auth(binddn, password)
          status 401

          result = ldap.get_operation_result
          message = "Couldn't authenticate with #{binddn} (#{result.code}: #{result.message})"
          log message
          return({status: 401, message: message})
        end

        attributes = %w(dn sAMAccountName userPrincipalName)

        users = case
        when is_upn
          log "Searching entry with (userPrincipalName=#{escape_for_filter(binddn)})"
          ldap.search(filter: "(userPrincipalName=#{escape_for_filter(binddn)})", attributes: attributes)
        when is_dn
          path = binddn.split(?,)
          filter = path.shift
          log "Searching entry with (#{filter}), base #{path.join(?,)}"
          ldap.search(base: path.join(?,), filter: "(#{filter})", attributes: attributes)
        else
          log "Searching entry with (userPrincipalName=#{escape_for_filter(binddn)})"
          ldap.search(filter: "(userPrincipalName=#{escape_for_filter(binddn)})", attributes: attributes)
        end
        user = users && users.first

        unless user
          status 400
          message = "couldn't find entry for user #{binddn}"
          log message
          return({status: 400, message: message})
        end

        return nil, ldap, user
      end
    end

    get '/' do
      message = case params[:message]
      when 'success'
        {notice: "Successfully changed"}
      end

      erb :index, locals: message
    end

    post '/change' do
      unless %i(new_password new_password_confirmation password login).all? { |k| params[k] && params[k] != '' }
        status 400
        next erb(:index, locals: {error: 'missing parameters'})
      end

      if params[:new_password] != params[:new_password_confirmation]
        status 400
        next erb(:index, locals: {error: 'password confirmation did not match'})
      end

      error, ldap, user = bind(params[:login], params[:password])
      if error
        status error[:status]
        next erb(:index, locals: {error: error[:message]})
      end

      log "Changing password for '#{user.dn}'"

      ops = [[:delete, :unicodePwd, encode_unicodepwd(params[:password])], [:add, :unicodePwd, encode_unicodepwd(params[:new_password])]]

      unless ldap.modify(dn: user.dn, operations: ops)
        status 400

        result = ldap.get_operation_result
        next erb(:index, locals: {error: "Couldn't update password for #{user.dn} (#{result.code}: #{result.message})"})
      end

      redirect '/?message=success'
    end

    post '/test' do
      error, ldap, user = bind(params[:login], params[:password])
      if error
        status error[:status]
        next erb(:index, locals: {error: error[:message]})
      end

      log "tested: #{user.dn}, #{user.userprincipalname}"

      erb(:index, locals: {notice: "you are #{user.dn} #{user.userprincipalname}"})
    end
  end
end
