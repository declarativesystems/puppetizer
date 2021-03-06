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
#
# puppetizer
# =====
# SIMPLE way of installing PE over SSH


require 'inistyle'
require 'net/ssh/simple'
require 'escort'
require 'erb'
require 'tempfile'
require 'ruby-progressbar'
require 'time'
require 'puppetizer'
require 'puppetizer/alt_installer'
require 'puppetizer/transport'
require 'puppetizer/transport/secure_shell'
require 'puppetizer/transport/local'
require 'puppetizer/util'
require 'puppetizer/log'
require 'puppetizer/puppetizer_error'
require 'puppetizer/authenticator'
require 'puppetizer/ssh_params'
require 'puppetizer/inventory_parser'
require 'puppetizer/install_state'

module Puppetizer
  INSTALL_PUPPET_TEMPLATE     = './templates/install_puppet.sh.erb'
  INSTALL_PE_MASTER_TEMPLATE  = './templates/install_pe_master.sh.erb'
  INSTALL_CM_TEMPLATE         = './templates/install_cm.sh.erb'
  PE_POSTINSTALL_TEMPLATE     = './templates/pe_postinstall.sh.erb'
  PUPPET_STATUS_TEMPLATE      = './templates/puppet_status.sh.erb'
  CSR_ATTRIBUTES_TEMPLATE     = './templates/csr_attributes.yaml.erb'
  SETUP_CODE_MANAGER_TEMPLATE = './templates/setup_code_manager.sh.erb'
  OFFLINE_GEM_TEMPLATE        = './templates/offline_gem.sh.erb'
  SIGN_CM_CERT_TEMPLATE       = './templates/sign_cm_cert.sh.erb'
  LB_EXTERNAL_FACT_TEMPLATE   = './templates/lb_external_fact.sh.erb'
  MV_CSR_ATTRIBUTES_TEMPLATE  = './templates/mv_csr_attributes.sh.erb'

  CLASSIFY_CM_SCRIPT          = './scripts/classify_cm.rb'

  PUPPET_PATH         = '/opt/puppetlabs/puppet/bin'
  PUPPET_ETC          = '/etc/puppetlabs'
  PUPPET_CONFDIR      = "#{PUPPET_ETC}/puppet"
  PUPPET_R10K_SSH     = "#{PUPPET_ETC}/puppetserver/ssh"
  PUPPET_R10K_KEY     = "#{PUPPET_R10K_SSH}/id-control_repo.rsa"
  INVENTORY_FILE = 'inventory/hosts'

  AGENT_LOCAL_PATH          = './agent_installers'
  AGENT_UPLOAD_PATH_NORMAL  = '/opt/puppetlabs/server/data/staging/pe_repo-puppet-agent-1.7.1/'
  AGENT_UPLOAD_PATH_WINDOWS_X86 =
    '/opt/puppetlabs/server/data/packages/public/2016.4.2/windows-i386-1.7.1/'
  AGENT_UPLOAD_PATH_WINDOWS_X64 =
    '/opt/puppetlabs/server/data/packages/public/2016.4.2/windows-x86_64-1.7.1'
  GEM_LOCAL_PATH      = './gems'

  class Puppetizer < ::Escort::ActionCommand::Base

    def initialize(options, arguments)
      @options        = options
      @arguments      = arguments
      @ssh_username   = @options[:global][:options][:ssh_username]
      @reinstall      = @options[:global][:options][:reinstall]
      @local          = @options[:global][:options][:local]
      @authenticator  = Authenticator.new(
        @options[:global][:options][:password_file], @ssh_username
      )

      if @local
        @transport = Transport::Local
        @myini = {
          "puppetmasters" => [ "localhost"]
        }
      else
        @transport = Transport::SecureShell

        if File.exists?(INVENTORY_FILE)
          @myini = IniStyle.new('inventory/hosts')
        else
          raise Escort::UserError.new("Inventory file not found at #{INVENTORY_FILE}")
        end
      end
      # split the only_hosts list by on commas if present
      if @options[:global][:options][:only_hosts] == nil or
            @options[:global][:options][:only_hosts].empty?
        @only_hosts = false
      else
        @only_hosts = @options[:global][:options][:only_hosts].downcase.split(',')
      end


    end

    def setup_csr_attributes(ssh_params, csr_attributes, data)
      challenge_password = @options[:global][:commands][command_name][:options][:challenge_password]
      user_start, user_end = ssh_params.get_swap_user()

      if csr_attributes or challenge_password
        Escort::Logger.output.puts "Setting up CSR attributes on #{ssh_params.get_hostname()}"
        f = Tempfile.new("puppetizer")
        begin
          f << ERB.new(Util::resource_read(CSR_ATTRIBUTES_TEMPLATE), nil, '-').result(binding)
          f.close
          csr_tmp = "/tmp/csr_attributes.yaml"
          @transport::scp(ssh_params, f.path, csr_tmp)
          @transport::ssh(ssh_params,
            ERB.new(Util::resource_read(MV_CSR_ATTRIBUTES_TEMPLATE), nil, '-').result(binding))
        ensure
          f.close
          f.unlink
        end
      end
    end

    def install_puppet(hostname, csr_attributes = false, data={})
      message = "Installing puppet agent on #{hostname}"
      Escort::Logger.output.puts message
      Log::action_log('# ' + message)

      # puppet master to use
      if @options[:global][:commands][:agents][:options][:puppetmaster]
        puppetmaster = @options[:global][:commands][:agents][:options][:puppetmaster]
      elsif data.has_key?('pm') and ! data['pm'].empty?
        puppetmaster = data['pm']
      else
        raise Escort::UserError.new(
          "must specify puppetmaster address for #{hostname} in inventory file, "\
          "eg pm=xxx.megacorp.com or on the commandline with --puppetmaster")
      end

      # pp_role (set via CLI - overrides anything set in inventory file)
      if @options[:global][:commands][command_name][:options][:pp_role]
        data["pp_role"] = @options[:global][:commands][command_name][:options][:pp_role]
      end

      ssh_params = SshParams.new(hostname, @authenticator)
      user_start, user_end = ssh_params.get_swap_user()


  #    challenge_password = @options[:global][:commands][command_name][:options][:challenge_password]
  #    csr_attributes |= challenge_password
      setup_csr_attributes(ssh_params, csr_attributes, data)

      if @options[:global][:commands][:agents][:options][:alt_installer]
        AltInstaller::install_puppet(ssh_params, puppetmaster, data)
      else
        @transport::ssh(ssh_params, ERB.new(Util::resource_read(INSTALL_PUPPET_TEMPLATE), nil, '-').result(binding))
      end

      InstallState::mark_installed(hostname)
    end

    def find_pe_tarball
      tarballs = Dir.glob("./puppet-enterprise-20*.tar.gz")
      if tarballs.empty?
        raise Escort::UserError.new("Please download Puppet Enterprise and put the tarball in #{Dir.pwd}")
      else
        tarballs.last
      end
    end



    def upload_agent_installers(hostname)
      ssh_params = SshParams.new(hostname, @authenticator)
      user_start, user_end = ssh_params.get_swap_user()
      if Dir.exists?(AGENT_LOCAL_PATH)
        # make sure the final location exists on puppet master
        @transport::ssh(ssh_params, "#{user_start} mkdir -p #{AGENT_UPLOAD_PATH_NORMAL} #{AGENT_UPLOAD_PATH_WINDOWS_X86} #{AGENT_UPLOAD_PATH_WINDOWS_X64} #{user_end}")
        Dir.foreach(AGENT_LOCAL_PATH) { |f|
          if f != '.' and f != '..'
            filename = AGENT_LOCAL_PATH + File::SEPARATOR + f
            @transport::scp(ssh_params, filename, "/tmp/#{f}", "Uploading #{f}")

            if f =~ /.msi/
              if f =~ /x86/
                final_destination = AGENT_UPLOAD_PATH_WINDOWS_X86
              else
                final_destination = AGENT_UPLOAD_PATH_WINDOWS_X64
              end
            else
              final_destination = AGENT_UPLOAD_PATH_NORMAL
            end
            @transport::ssh(ssh_params, "#{user_start} cp /tmp/#{f} #{final_destination} #{user_end}")
          end
        }
      end
    end

    def upload_offline_gems(hostname)
      ssh_params = SshParams.new(hostname, @authenticator)
      user_start, user_end = ssh_params.get_swap_user()

      gem_cache_dir = '/tmp/gems/'
      install_needed = false
      local_cache = GEM_LOCAL_PATH + File::SEPARATOR + 'cache'
      if Dir.exists?(local_cache)
        @transport::ssh(ssh_params, "mkdir -p #{gem_cache_dir}")
        Dir.foreach(local_cache) { |f|
          if f != '.' and f != '..'
            filename = local_cache + File::SEPARATOR + f
            @transport::scp(ssh_params, filename, gem_cache_dir + f, "Uploading " + f)
            install_needed = true
          end
        }

        if install_needed
          @transport::ssh(ssh_params, ERB.new(Util::resource_read(OFFLINE_GEM_TEMPLATE), nil, '-').result(binding))
        end
      end
    end

    def run_puppet(ssh_params, message="Running puppet...")
      user_start, user_end = ssh_params.get_swap_user()

      Escort::Logger.output.puts message
      Log::action_log("# --- begin run command on #{ssh_params.get_hostname()} ---")
      @transport::ssh(ssh_params, "#{user_start} /opt/puppetlabs/bin/puppet agent -t #{user_end}")
      Log::action_log("# --- end run command on #{ssh_params.get_hostname()} ---")
      Escort::Logger.output.puts "...done!"
    end

    def install_pe(hostname, csr_attributes, data)
      message = "Installing Puppet Enterprise on #{hostname}"
      Escort::Logger.output.puts message
      Log::action_log('# ' + message)

      # ssh params for the host we are currently processing
      ssh_params = SshParams.new(hostname, @authenticator)
      user_start, user_end = ssh_params.get_swap_user()

      # variables in scope for ERB
      password = @options[:global][:commands][command_name][:options][:console_admin_password]

      # pp_role (set via CLI - overrides anything set in inventory file)
      if @options[:global][:commands][command_name][:options][:pp_role]
        data["pp_role"] = @options[:global][:commands][command_name][:options][:pp_role]
      end

      # compile master installation?
      if data.has_key?('compile_master') and data['compile_master'] == "true"
        compile_master = true
        if data.has_key?('mom') and ! data['mom'].empty?
          mom = data['mom']
          # ssh params for the MoM we need (must already be up)
          ssh_params_mom = SshParams.new(mom, @authenticator)
        else
          raise PuppetizerError, "You must specify a mom when installing compile masters.  Please set mom=PUPPETMASTER_FQDN"
        end

        if data.has_key?('lb') and ! data['lb'].empty?
          # if we are using a loadblancer with pe_repo, we must use a VARIABLE
          # so that if there are regional/multiple loadbalancers we can pick the
          # right one.  later on, we will dump the loadbalancer name as an external
          # fact (there's no suitable place in $trusted for it to live).
          # note - we backslash the $ to prevent BASH from interpretting it when
          # we call our ruby script with the value
          lb_fact = '\$puppet_load_balancer'
          lb_host = data['lb']
        else
          lb_fact = ''
          lb_host = ''
        end
      else
        compile_master = false

        if data.has_key?('r10k_private_key') and ! data['r10k_private_key'].empty?
          r10k_private_key_path = Dir.pwd + File::SEPARATOR + data['r10k_private_key']
          if ! File.exists?(r10k_private_key_path)
            raise PuppetizerError, "r10k_private_key not found at #{r10k_private_key_path}"
          end
        else
          r10k_private_key_path = false
        end
      end

      # deploy code with code manager?
      if data.has_key?('deploy_code') and data['deploy_code'] == "true"
        deploy_code = true
      else
        # if control repo set, deploy code
        deploy_code =  @options[:global][:commands][command_context[0]][:options][:control_repo] != nil
      end

      # use control repo supplied in inventory else command line default
      if data.has_key?('control_repo') and ! data['control_repo'].empty?
        control_repo = data['control_repo']
      else
        control_repo = @options[:global][:commands][command_context[0]][:options][:control_repo]
      end

      # dns_alt_names from inventory
      if data.has_key?('dns_alt_names') and ! data['dns_alt_names'].empty?
        # each pair needs to be wrapped in double quotes
        dns_alt_names = data['dns_alt_names'].split(',').map { |s| '"' + s + '"'}.join(',')
      else
        dns_alt_names = false
      end

      setup_csr_attributes(ssh_params, csr_attributes, data)

      # SCP up the agents if present
      upload_agent_installers(hostname)

      # run the PE installer
      if compile_master
        # create an external fact with the address of the load balancer on the host
        @transport::ssh(ssh_params,
          ERB.new(Util::resource_read(LB_EXTERNAL_FACT_TEMPLATE), nil, '-').result(binding))

        # install puppet agent as a CM
        @transport::ssh(ssh_params,
          ERB.new(Util::resource_read(INSTALL_CM_TEMPLATE), nil, '-').result(binding))

        # sign the cert on the mom
        Escort::Logger.output.puts "Waiting 5 seconds for CSR to arrive on MOM"
        sleep(5)
        Log::action_log("# --- begin run command on #{mom} ---")
        @transport::ssh(ssh_params_mom,
          ERB.new(Util::resource_read(SIGN_CM_CERT_TEMPLATE), nil, '-').result(binding))
        Log::action_log("# --- end run command on #{mom} ---")

        # copy the classification script to the MOM and run it
        Escort::Logger.output.puts "Classifying #{hostname} as Compile Master"
        script_path = "/tmp/#{File.basename(CLASSIFY_CM_SCRIPT)}"

        Log::action_log("# --- begin copy file to #{mom} ---")
        @transport::scp(ssh_params_mom, Util::resource_path(CLASSIFY_CM_SCRIPT), script_path)
        Log::action_log("# --- end copy file to #{mom} ---")

        # pin the CM to the PE Masters group and set a load balancer address for
        # pe_repo (if provided)
        Log::action_log("# --- begin run command on #{mom} ---")
        @transport::ssh(ssh_params_mom, "chmod +x #{script_path}")
        @transport::ssh(ssh_params_mom, "#{user_start} #{script_path} #{hostname} #{lb_fact} #{user_end}")
        Log::action_log("# --- end run command on #{mom} ---")

        # Run puppet in the correct order
        run_puppet(ssh_params, "Running puppet on compile master: #{hostname}")
        run_puppet(ssh_params_mom, "Running puppet on MOM: #{mom}")
      else
        # full PE installation

        # SCP the installer
        tarball = find_pe_tarball
        @transport::scp(ssh_params, tarball, "/tmp/#{tarball}", "Upload PE Media")

        # copy r10k private key if needed
        if r10k_private_key_path

          # upload to /tmp
          temp_keyfile = "/tmp/#{File.basename(PUPPET_R10K_KEY)}"
          @transport::scp(ssh_params, r10k_private_key_path, temp_keyfile)

          # make directory and move temp keyfile there
          @transport::ssh(ssh_params, "#{user_start} mkdir -p #{PUPPET_R10K_SSH} #{user_end}")
          @transport::ssh(ssh_params, "#{user_start} mv #{temp_keyfile} #{PUPPET_R10K_KEY} #{user_end}")
        end

        # run installation
        @transport::ssh(ssh_params, ERB.new(Util::resource_read(INSTALL_PE_MASTER_TEMPLATE), nil, '-').result(binding))

        # fix permissions on key
        if r10k_private_key_path
          @transport::ssh(ssh_params, "#{user_start} chown pe-puppet.pe-puppet #{PUPPET_R10K_KEY} #{user_end}")
          @transport::ssh(ssh_params, "#{user_start} chmod 600 #{PUPPET_R10K_KEY} #{user_end}")
        end
      end

      # Upload the offline gems if present - must be done AFTER puppet install
      # to obtain gem command
      upload_offline_gems(hostname)

      # post-install (gems) after we have uploaded any offline gems
      @transport::ssh(ssh_params,
        ERB.new(Util::resource_read(PE_POSTINSTALL_TEMPLATE), nil, '-').result(binding))

      # run puppet to finalise configuration
      run_puppet(ssh_params)

      if deploy_code and ! compile_master
        setup_code_manager(ssh_params)
      end

      InstallState::mark_installed(hostname)
      Escort::Logger.output.puts "Puppet Enterprise installation for #{hostname} completed"
    end


    def puppetize_agent()
      @myini['agents'].each do |r|
        hostname, csr_attributes, data = InventoryParser::parse(r)
        if should_process_host(hostname.downcase)
          begin
            install_puppet(hostname, csr_attributes, data)
            processed_host(hostname)
          rescue PuppetizerError => e
            Escort::Logger.error.error e.message
          end
        end
      end

      if @only_hosts
        @only_hosts.each do |hostname|
          Escort::Logger.output.puts
            "#{hostname} has no entry in inventory but installing as you have requested..."
          begin
            install_puppet(hostname)
          rescue PuppetizerError => e
            Escort::Logger.error.error e.message
          end
        end
      end
    end

    def should_process_host(hostname)
      hostname = hostname.downcase

      # First see if we should only be processing specific hosts...
      if @only_hosts
        if @only_hosts.include?(hostname)
          process = true
        else
          process = false
        end
      else
        process = true
      end

      if process
        # see if we have already installed this host
        if InstallState::installed(hostname)
          if @reinstall
            Escort::Logger.output.puts(
              "#{hostname} already installed, reinstalling as you requested")
            process = true
          else
            Escort::Logger.output.puts("#{hostname} already installed, skipping")
            process = false

            # remove from @only_hosts to prevent us trying to do it as a special
            # order...
            if @only_hosts
              @only_hosts.delete(hostname)
            end
          end
        end
      end
      process
    end

    def processed_host(hostname)
      if @only_hosts
        @only_hosts.delete(hostname)
      end
    end

    def puppetize_master()
      @myini['puppetmasters'].each do |r|
        hostname, csr_attributes, data = InventoryParser::parse(r)
        if should_process_host(hostname)
          begin
            install_pe(hostname, csr_attributes, data)
            processed_host(hostname)
          rescue PuppetizerError => e
            Escort::Logger.error.error e.message
          end
        end
      end

      if @only_hosts and (! @only_hosts.empty?)
        Escort::Logger.error.error(
          "The following hosts were requested for installation but have no "\
          "corresponding entry in the inventory file: #{@only_hosts}")
      end
    end

    def print_status(hostname)
      ssh_params = SshParams.new(hostname, @authenticator)
      user_start, user_end = ssh_params.get_swap_user()

      begin
        print "host #{hostname} status: "
        @transport::ssh(ssh_params,
          ERB.new(Util::resource_read(PUPPET_STATUS_TEMPLATE), nil, '-').result(binding))
      rescue PuppetizerError => e
        Escort::Logger.error.error e.message
      end
    end

    def status()
      @myini.sections.each do |section|
        @myini[section].each do |r|
          hostname, csr_attributes, data = InventoryParser::parse(r)
          if should_process_host(hostname)
            print_status(hostname)
            processed_host(hostname)
          end
        end
      end

      if @only_hosts
        @only_hosts.each do |hostname|
          print_status(hostname)
        end
      end
    end

    def setup_code_manager(ssh_params)
      Escort::Logger.output.puts "Setting up Code Manager on #{ssh_params.get_hostname()}"
      user_start, user_end = ssh_params.get_swap_user()

      @transport::ssh(ssh_params,
        ERB.new(Util::resource_read(SETUP_CODE_MANAGER_TEMPLATE), nil, '-').result(binding))
    end

    def action_upload_agent_installers()
      section_key = "puppetmasters"
      if @myini.sections.include?(section_key)
        @myini[section_key].each do |r|
          hostname, csr_attributes, data = InventoryParser::parse(r)
          if should_process_host(hostname)
            upload_agent_installers(hostname)
          end
        end
      end

      if @only_hosts
        @only_hosts.each do |hostname|
          Escort::Logger.output.puts
            "#{hostname} has no entry in inventory but uploading agent installers as requested..."
          upload_agent_installers(hostname)
        end
      end
    end

    def action_upload_offline_gems()
      section_key = "puppetmasters"
      if @myini.sections.include?(section_key)
        @myini[section_key].each do |r|
          hostname, csr_attributes, data = InventoryParser::parse(r)
          if should_process_host(hostname)
            upload_offline_gems(hostname)
            processed_host(hostname)
          end
        end
      end
      if @only_hosts
        @only_hosts.each do |hostname|
          Escort::Logger.output.puts
            "#{hostname} has no entry in inventory but uploading gems as requested..."
          upload_offline_gems(hostname)
        end
      end
    end

    def classify()
      puts "hello"
    end
  end
end
