require 'adchpasswd'
require 'logger'

ENV['ADCHPASSWD_LDAP_TLS'] ||= '1'

use Rack::CommonLogger, Logger.new($stdout)

run Adchpasswd.app(
  ldap: {
    host: ENV['ADCHPASSWD_LDAP_HOST'],
    port: ENV['ADCHPASSWD_LDAP_PORT'] ? ENV['ADCHPASSWD_LDAP_PORT'].to_i : (ENV['ADCHPASSWD_LDAP_TLS'] == '1' ? 636 : 384),
    base: ENV['ADCHPASSWD_LDAP_BASE_DN'],
    encryption: ENV['ADCHPASSWD_LDAP_TLS'] == '1' ? :simple_tls : nil,
  },
  default_upn_suffix: ENV['ADCHPASSWD_DEFAULT_UPN_SUFFIX'],
)
