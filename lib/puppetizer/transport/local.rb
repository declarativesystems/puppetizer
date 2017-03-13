#!/usr/bin/env ruby
#
# Copyright 2016 Geoff Williams for Puppet Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
require 'net/ssh/simple'
require 'open3'
require 'pty'
require 'puppetizer/puppetizer_error'
require 'puppetizer/log'
require 'puppetizer/busy_spinner'
require 'puppetizer/authenticator'
require 'puppetizer/transport'

module Puppetizer
  module Transport
    Log = Puppetizer::Log
    PuppetizerError = Puppetizer::PuppetizerError
    module Local

      def self.upload_needed(ssh_params, local_file, remote_file)
        local_md5=%x{md5sum #{local_file}}.strip.split(/\s+/)[0]
        remote_md5=%x{md5sum #{remote_file} 2>&1}.strip.split(/\s+/)[0]

        needed = local_md5 != remote_md5
        if ! needed
          Escort::Logger.output.puts "#{local_md5} #{File.basename(local_file)}"
        end
        return needed
      end

      def self.scp(ssh_params, local_file, remote_file, job_name='Upload data')
        if upload_needed(ssh_params, local_file, remote_file)
          Log::action_log("cp #{local_file} to #{remote_file}")

          begin
            # ssh_opts = ssh_params.get_ssh_opts()
            FileUtils.cp(local_file, remote_file)
            Escort::Logger.output.puts "Copied #{local_file} to #{remote_file} OK"
          rescue Exception => e
            raise PuppetizerError, "Error copying file: #{local_file} to #{remote_file}"
          end
        end
      end

      # This really takes the biscuit!  Can anyone see a better way to do this
      # locally?
      def self.ssh(ssh_params, cmd, no_print=false, no_capture=false)

        # escape double quotes and dollars to prevent bash expansion - quotes to
        # avoid clashing with bash -c "", $ to prevent empty variables appearing
        # Note that we must use "" as the 'outer' quotes since bash doesn't
        # respect \' inside single quotes!
        cmd_quoted = cmd.strip.gsub('"','\\"').gsub('$','\\$')

        # unset ruby/bundle variables to prevent failed command from using the
        # wrong ruby, then wrap the quoted command in bash -c, otherwise shell
        # redirection '>' and friends will fail
        cmd_wrapped = "unset RUBYLIB GEM_HOME GEM_PATH RUBYOPT;  bash -c \"#{cmd_quoted}\""
        Log::action_log(cmd_wrapped)

        # run the command (PTY.spawn works but fails at the end for some reason)
        begin
          Open3.popen2e(cmd_wrapped) { | w, r,  wait_thr|
            r.sync
            r.each_line { |line|
              process_line(line,w,no_print, ssh_params)
            }

            if wait_thr.value.exitstatus == 0
              Escort::Logger.output.puts "Command executed OK"
            else
              raise PuppetizerError, "Command failed!"
            end
          }
        rescue Errno::ENOENT => e
          raise PuppetizerError, "Command missing or file not found: #{cmd_wrapped}"
        end
      end

      def self.process_line(d, channel, no_print, ssh_params)
        # The sudo prompt doesn't have a newline at the end so the main stream
        # reading code never catches it, lets capture it here...
        # based on: http://stackoverflow.com/a/4235463
        if d =~ /^\[sudo\] password for #{ssh_params.get_username()}:/ or d =~ /Password:/
          if ssh_params.get_swap_user()[2] == :sudo
            if ssh_params.get_user_password()
              # send password
              channel.puts ssh_params.get_user_password()

              # don't forget to press enter :)
              channel.puts "\n"
            else
              raise PuppetizerError,
                "We need a sudo password.  Please export PUPPETIZER_USER_PASSWORD=xxx"
            end
          elsif ssh_params.get_swap_user()[2] == :su
            if ssh_params.get_root_password()
              # send password
              channel.puts ssh_params.get_root_password()
              channel.puts "\n"
            else
              raise PuppetizerError,
                "We need an su password.  Please export PUPPETIZER_ROOT_PASSWORD=xxx"
            end
          else
            raise PuppetizerError,
              "System at #{ssh_params.get_hostname()} requesting password but we "\
              "don't have one configured"
          end
        end

        Escort::Logger.output.puts d.strip
      end
    end
  end
end
