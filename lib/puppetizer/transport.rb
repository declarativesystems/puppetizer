# #!/usr/bin/env ruby
# #
# # Copyright 2016 Geoff Williams for Puppet Inc.
# #
# # Licensed under the Apache License, Version 2.0 (the "License");
# # you may not use this file except in compliance with the License.
# # You may obtain a copy of the License at
# #
# #   http://www.apache.org/licenses/LICENSE-2.0
# #
# # Unless required by applicable law or agreed to in writing, software
# # distributed under the License is distributed on an "AS IS" BASIS,
# # WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# # See the License for the specific language governing permissions and
# # limitations under the License.
module Puppetizer
  module Transport

  end
end


# require 'net/ssh/simple'
# require 'puppetizer/puppetizer_error'
# require 'puppetizer/log'
# require 'puppetizer/busy_spinner'
# require 'puppetizer/authenticator'
#
# module Puppetizer
#   class Transport
#     Log = Puppetizer::Log
#     PuppetizerError = Puppetizer::PuppetizerError
#
#     def initialize(transport_module)
#       @transport = transport_module
#     end
#
#     def self.scp(ssh_params, local_file, remote_file, job_name='Upload data')
#       @transport.scp(ssh_params, local_file, remote_file, job_name)
#     end
#
#     def self.ssh(ssh_params, cmd, no_print=false, no_capture=false)
#       @transport.ssh(ssh_params, cmd, no_print, no_capture)
#     end
#
#   end
# end
