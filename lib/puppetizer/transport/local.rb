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

      # adapted from https://nickcharlton.net/posts/ruby-subprocesses-with-stdout-stderr-streams.html
      def self.ssh(ssh_params, cmd, no_print=false, no_capture=false)
        Log::action_log(cmd)
        require 'pty'
        #Open3.popen2e(cmd) { |stdin, stdout_and_stderr, wait_thr|
        PTY.spawn(cmd) { | r, w, pid|
          begin
            r.sync
            # # read each stream from a new thread
            # puts stdout.gets
            # puts stderr.gets
            # { :out => stdout, :err => stderr }.each do |key, stream|
            #   Thread.new do
            #     until (raw_line = stream.gets).nil? do
            #       puts "**** #{raw_line}"
            #       defrag_line(raw_line,stdin,no_print, ssh_params)
            #     end
            #   end
            # end
            r.each_line { |line|
              process_line(line,w,no_print, ssh_params)
            }
          # thread.join # don't exit until the external process is done
          #exit_status = .value

          rescue Errno::EIO => e
            raise PuppetizerError, "Command failed mid-stream"
          end

        }
        if $?.exitstatus == 0
          Escort::Logger.output.puts "Command executed OK"
        else
          raise PuppetizerError, "Command failed!"
        end

        # rescue Net::SSH::Simple::Error => e
        #   if e.message =~ /AuthenticationFailed/
        #     error_message = "Authentication failed for #{ssh_opts[:user]}@#{host}, key loaded?"
        #   else
        #     error_message = e.message
        #   end
        #   raise PuppetizerError, error_message
        # end
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
