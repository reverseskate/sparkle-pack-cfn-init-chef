SfnRegistry.register(:chef_client) do |_name, _config={}|

  chef_bucket = _config.fetch(:chef_bucket)

  first_run = _config.fetch(:attributes, {}).merge(
    :stack => {
      :name => stack_name!,
      :id => stack_id!,
      :region => region!
    },
    :run_list => _config.fetch(:run_list, [])
  )

  metadata('AWS::CloudFormation::Authentication') do
    chef_s3_auth do
      set!('roleName'._no_hump, _config.fetch(:auth_role))
      set!('buckets'._no_hump, [ chef_bucket ])
      set!('type'._no_hump, 'S3')
    end
  end

  metadata('AWS::CloudFormation::Init') do
    _camel_keys_set(:auto_disable)
    configSets do |sets|
      sets.default.concat(['chef_client'])
    end
    chef_client do
      files('/etc/chef/validation.pem') do
        source join!(
          'https://', chef_bucket, '.s3.amazonaws.com/', 'validation.pem'
        )
        mode '000400'
        owner 'root'
        group 'root'
        authentication 'ChefS3Auth'
      end
      if _config[:data_bag_secret]
        files('/etc/chef/encrypted_data_bag_secret') do
          source join!(
            'https://', chef_bucket, '.s3.amazonaws.com/', 'encrypted_data_bag_secret'
          )
          mode '000400'
          owner 'root'
          group 'root'
          authentication 'ChefS3Auth'
        end
      end
      files('/etc/chef/client.rb') do
        content join!(
          "chef_server_url '", _config.fetch(:chef_server), "'\n",
          "environment '", _config.fetch(:chef_environment, '_default'), "'\n",
          "log_location '/var/log/chef/client.log'\n",
          "validation_client_name '", _config.fetch(:validation_client), "'\n"
        )
        mode '000400'
        owner 'root'
        group 'root'
      end
      files('/etc/chef/first_run.json') do
        content first_run
      end
      commands('00_install_chef') do
        command join!("curl -sSL https://omnitruck.chef.io/install.sh | sudo bash -s -- -v ", _config.fetch(:chef_version, 'latest'))
      end
      commands('01_log_dir') do
        command 'mkdir /var/log/chef'
        test 'test ! -e /var/log/chef'
      end
      # Why is this still a problem, Chef?
      commands('02_create_ec2_hints_file') do
        command 'mkdir -p /etc/chef/ohai/hints && touch /etc/chef/ohai/hints/ec2.json'
        test 'test ! -e /etc/chef/ohai/hints/ec2.json'
      end
      commands('03_chef_first_run') do
        command 'chef-client -j /etc/chef/first_run.json'
      end
      commands('03_remove_validation_pem') do
        command 'rm /etc/chef/validation.pem'
        test 'test -e /etc/chef/client.pem'
      end
    end
  end
end
