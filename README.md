# Puppetizer

* This is experimental software, use at own risk!
* This software is not supported by Puppet, Inc.
* Puppetizer works by running commands over SSH to install and configure you master, in essence, it performs the same steps that a human operator would do, only faster
* In the case of installation problems, users should attempt to replicate error in a non-automated environment (eg, without this tool and by running the puppet installation scripts manually), as Puppet, Inc *do* provide support for the installer shipped within their installation media


## Development instructions

### Prerequisites
#### On the machine talking to the puppetmaster

##### ruby (on RHEL 7)

```shell
yum install -y ruby ruby-devel rubygems git
```
_Note:  This will install the system ruby - you don't need to (nor should you...) install this software on a Puppet Enterprise Master_

##### ruby (on RHEL 6)
RHEL 6 ships ruby 1.8.7 which is ancient.  You will need a newer ruby (2.0 works well) to use this tool.  Please contact your system administrator for details of how to install and configure ruby 2 through RHEL software collections.

##### bundler

```shell
gem install bundler
```

#### On the puppetmaster
* The `Development Tools` group package needs to be installed (some of the gems we use need it)

```shell
yum groupinstall 'Development Tools'
```

## Obtain Puppetizer
```shell
git clone https://github.com/GeoffWilliams/puppetizer
```

Where `...` represents the arguments to the puppetizer command


# Preparing to run puppetizer

* Puppetizer needs a directory tree to be setup on your machine with files to upload and the names of the machines to connect to, etc
* The directory can be anywhere you like as long as the files are accessible to you
* The machine you run from doesn't need internet access, you can SCP files to the locations it needs and then it will upload them for you

## Directory Layout
After following the instructions below, the directory to run puppetizer from should look something like this:

```
├── agent_installers                                  # Agent installers to upload to master
│   ├── puppet-agent-1.7.1-1.el4.i386.rpm
│   ├── puppet-agent-1.7.1-1.el4.x86_64.rpm
│   ├── ...
├── Gemfile                                           # Location of puppetizer
── gems                                               # Gems to upload to master
│   ├── bin
│   ├── ...
├── inventory
│   └── hosts
├── license.key                                       # Licence key to upload to master
├── puppet-enterprise-2016.4.2-el-7-x86_64.tar.gz     # Installation media
```

### Gemfile
The `Gemfile` tells ruby where to find the puppetizer library on your system.  Please see the example [Gemfile](doc/Gemfile) and customise with either the checked out location of puppetizer and net-ssh-simple (if offline) otherwise, the example can be used as-is.

Once the Gemfile is in place, please run the following commands to setup ruby:

```shell
cd puppetizer
bundle install
bundle exec ./puppetizer ...
```

### Inventory file
Puppetizer uses an inventory file to identify nodes to install puppet enterprise components on.  Please see [inventory file](doc/inventory/hosts) for an example and customise according to your needs as follows:

* Under the `[puppetmasters]` heading, list the address(es) of hosts to install as monolithic masters
* Under the `[agents]` heading, list the address(es) of hosts to install as agents
* For each node, specify `pp_role` if you would like to assign a role class via CSR attributes
* For your master, set `deploy_code=true` to checkout an R10K control repo
* Use `--control-repo` when running puppetizer to specify the location of the control repo

The file should be saved as `./inventory/hosts` in the directory you want to run puppetizer from.

### Puppet Enterprise installation media
* Please obtain a copy of Puppet Enterprise from [puppet.com](puppet.com) and place the tarball in the directory you want to run puppetizer from

### Offline
Sometimes your puppetmaster will have no internet access or internet downloads for gems, agents etc are slowing you down.  In this case, puppetizer has support to upload the files needed from a local directory to keep you moving.

#### Agent installers
Puppetizer will upload and install all agent installation media found in the `./agent_installers` directory relative to where you are running the `puppetizer` command from:

* Please create a directory called `agent_installers` in the directory you want to run puppetizer from, then download the installers you want to upload to the Puppet Master from [puppet.com](puppet.com).

#### gem files
Puppetizer will upload and install all gems found in the `./gems` directory relative to where you are running the `puppetizer` command from:

* Please create a file called `gems` in the directory you want to run puppetizer from, then use the `gem` command to obtain a copy of the gems you need.
* A basic set of gems can be downloaded with the script at https://github.com/GeoffWilliams/puppetizer/blob/master/get_gems.sh


## Setup SSH authentication
By far the easiest and securest way to run puppetizer is to load keys into the SSH agent and not worry about things:

### Public Key based authentication
First start the agent
---------------------

```shell
eval `ssh-agent -s`
```

Now add your key
-----------------

```shell
ssh-add ssh_keys/id_rsa
```

If you don't yet have key based authentication in place, then its easiest to generate a new keypair locally and use ssh-copy-id to install it.  Mac users will need to `brew install ssh-copy-id` to obtain the command.  See https://valdhaus.co/writings/ansible-post-install/ for a worked example.

Alternatively, read on for details of how password based authentication works.

### Password based authentication

#### Environment variables
To stop passwords appearing in the process table, they are passed by exporting the variable `PUPPETIZER_USER_PASSWORD`, e.g.:

```shell
export PUPPETIZER_USER_PASSWORD=t0ps3cret
```

NOTES
-----
* `PUPPETIZER_USER_PASSWORD` will be sent to *all* machines puppetizer tries to connect to.  This is to avoid building huge lists of passwords for your important machines.  Your strongly encouraged to setup SSH public key based authentication(!)
* By default, puppetizer will try to connect as user `root`, choose a different user with the `--ssh-username` argument
* You may encounter the following error if you have SSH keys loaded in the SSH agent:

  ```shell
  disconnected: Too many authentication failures for root (2) @ #<Net::SSH::Simple::Result exception=#<Net::SSH::Disconnect: disconnected: Too many authentication failures for root (2)> finish_at=2016-09-25 23:54:48 +1000 stderr="" stdout="" success=false>
  ```

  In this case, the fix is to unload all loaded keys:

  ```shell
  ssh-add -D
  ```

#### Password file
The *last* resort in terms of passing passwords to SSH is to use a plaintext password file according to the following format:

```csv
hostname,username,password_user,password_root
puppet.demo.internal,geoff,abcd1234,abcd12341
lamp-b.demo.internal,geoff,abcd123,abcd1231
java-b.demo.internal,geoff,aladin123
```

Fields
------
* `hostname` - the hostname these details apply to
* `username` - the initial user to login as
* `password_user` - the password for the initial user, used with sudo if required
* `password_root` - the password for root, riggers switch to su

To activate the password file, pass the `--password-file FILENAME` argument, eg:

```shell
bundle exec puppetizer  --password-file passwords.txt puppetmasters
```

WARNING
-------
* Obviously building a list of hostnames, usernames and passwords is a *terrible* idea
* You really should use SSH keys for authentication
* ...But sometimes there is no choice.  Be sure to either:
  * Cycle passwords ASAP after deployment
  * Use puppet to change passwords after deployment

## Root access
Puppetizer needs to be able to gain access to the `root` account, the supported techniques are:
* Direct login as `root`
* Access `root` via sudo with no password
* Access `root` via sudo with the user's password
* Access `root` via su with `root`'s password

Important:  Puppetizer uses the presence of the password for `root` to see whether it needs to use `su` or `sudo`

### sudo
Login to machines as user `fred` and become root using `sudo` and `fred`'s password: `freddy123`.

If passwordless sudo is in use, omit the export of `PUPPETIZER_USER_PASSWORD`.

```shell
export PUPPETIZER_USER_PASSWORD=freddy123 # password for the user (for SSH)
puppetizer --ssh_username fred
```

### su
Login to machines as user `fred` and become `root` using `su` with password `topsecr3t`

```shell
export PUPPETIZER_USER_PASSWORD=freddy123 # password for the user (for SSH)
export PUPPETIZER_ROOT_PASSWORD=topsecr3t # password for root (asked by su)
puppetizer --ssh-username fred
```


# Usage
After following the above instructions, your able to use puppetizer to quickly install Puppet Enterprise masters and agents:

### Install Puppet Enterprise Masters
```shell
bundle exec puppetizer puppetmasters
```

### Install Puppet Agents
```shell
bundle exec puppetizer agents
```

## Inventory file format
*IMPORTANT*
Hosts are installed in the order specified in the file.  If you are setting up compile masters, make sure they are listed after the MOM they will install from!

### Sections
#### [puppetmasters]
* These machines will be configured as Puppet Enterprise masters
* One hostname per line, plus options

##### Options
* Any of the [pp_ options](https://docs.puppet.com/puppet/latest/reference/config_file_csr_attributes.html#puppet-specific-registered-ids), eg `pp_role=r_role::puppet::master`
* `dns_alt_names` - List of DNS alternative names for this server, eg `dns_alt_names=puppet,pe-puppet,jeditemple`
* `control_repo` - Control repo to setup code manager against, eg `control_repo=https://git.megacorp.com/puppet-control`
* `r10k_private_key` - Local path relative to current directory for r10k private private key file needed to access `control_repo`.  This file will be automatically uploaded to the master for you.
* `compile_master` - Set true to install this server as a Puppet Enterprise [Compile Master](https://docs.puppet.com/pe/latest/install_multimaster.html#how-compile-masters-work), eg `compile_master=true`
* `mom` - The address of the Puppet Enterprise [Master of Masters](https://docs.puppet.com/pe/latest/install_multimaster.html#how-compile-masters-work) to use for this Compile Master (mandatory if `compile_master=true`)
* `lb` - The address of the load balancer being used for compile masters, used to setup [pe_repo](https://docs.puppet.com/pe/latest/install_multimaster.html#step-4-if-using-load-balancers-configure-perepo-for-puppet-agent-installation)


#### [agents]
* These machines will be configured as Puppet Enterprise agents by [downloading the installer from the master using curl](https://docs.puppet.com/pe/latest/install_agents.html#scenario-1-the-puppet-master-and-agent-have-same-os-and-architecture)
* One hostname per line plus options

##### Options
* Any of the [pp_ options](https://docs.puppet.com/puppet/latest/reference/config_file_csr_attributes.html#puppet-specific-registered-ids), eg `pp_role=r_role::puppet::master`

## Tracking installation progress
Successful Master and Agent installations will create files under `./install_state` bearing the hostname of Successfully installed hosts.  To force reinstallation delete the corresponding file or pass `--reinstall` as a global option to puppetizer.

The presence of these files allows puppetizer to quickly skip hosts that have already been installed.

## Developing
After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Troubleshooting
* How to install pe

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/GeoffWilliams/puppetizer.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
