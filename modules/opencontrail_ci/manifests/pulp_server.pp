class opencontrail_ci::pulp_server(
  $pulp_version,
  $pulp_admin_password,
) inherits opencontrail_ci::params {

  include ::docker
  include ::epel
  include ::selinux

  firewall { '100 accept all to 80 - repos over http':
    proto  => 'tcp',
    dport  => '80',
    action => 'accept',
  }

  firewall { '101 accept all to 443 - repos over https + Pulp API':
    proto  => 'tcp',
    dport  => '443',
    action => 'accept',
  }

  firewall { '102 accept all to 5000 - docker registry':
    proto  => 'tcp',
    dport  => '5000',
    action => 'accept',
  }

  firewall { '103 accept all to 5001 - Pulp/crane registry':
    proto  => 'tcp',
    dport  => '5001',
    action => 'accept',
  }

  file { '/etc/httpd/conf.d/global-rewrite.conf':
    ensure => file,
    source => 'puppet:///modules/opencontrail_ci/pulp/global_rewrite.conf',
    mode   => '0600',
    owner  => 'root',
  }

  yumrepo { "pulp-${pulp_version}-stable":
    baseurl  => "https://repos.fedorapeople.org/repos/pulp/pulp/stable/${pulp_version}/\$releasever/\$basearch/",
    descr    => "Pulp ${pulp_version} Production Releases",
    enabled  => true,
    gpgcheck => true,
    gpgkey   => "https://repos.fedorapeople.org/repos/pulp/pulp/GPG-RPM-KEY-pulp-${pulp_version}",
  }

  class { '::pulp':
    require       => Class['epel'],
    crane_port    => '5001',
    enable_crane  => true,
    enable_docker => true,
    enable_rpm    => true,
    ssl_username  => false,
  }

  class { '::pulp::admin':
    enable_docker => true,
    require       => Class['pulp'],
  }

  # by default cert is only readable by root:apache, make it available for other
  # users as well
  exec { 'pulp-make-cacert-systemwide':
    command => "cp ${::pulp::ca_cert} /etc/pki/ca-trust/source/anchors/pulp_ca.crt && update-ca-trust enable && update-ca-trust extract",
    path    => '/bin',
    creates => '/etc/pki/ca-trust/source/anchors/pulp_ca.crt',
    require => Class['pulp'],
  }

  accounts::user { 'zuul':
    ensure        => present,
    comment       => 'Zuul Executor',
    home          => '/home/zuul',
    managehome    => true,
    purge_sshkeys => true,
    sshkeys       => [ hiera('zuul_ssh_public_key') ],
  }

  opencontrail_ci::pulp_repo_admin { 'root':
    username    => 'admin',
    password    => $pulp_admin_password,
    osuser      => 'root',
    osuser_home => '/root',
    require     => [ Service['pulp_resource_manager', 'httpd'], Class['pulp::admin'] ],
  }

  opencontrail_ci::pulp_repo_admin { 'zuul':
    username    => 'admin',
    password    => $pulp_admin_password,
    osuser      => 'zuul',
    osuser_home => '/home/zuul',
    require     => [ User['zuul'], Service['pulp_resource_manager', 'httpd'], Class['pulp::admin'] ],
  }

  selinux::port { 'crane':
    argument => '-m',
    context  => http_port_t,
    protocol => tcp,
    port     => 5001,
  }

  file { [ '/docker-registry', '/docker-registry/data' ]:
    ensure => directory,
    owner  => root,
    group  => root,
    mode   => '0700',
  }

  docker::run { 'registry':
    image   => 'registry:2',
    ports   => ['5000:5000'],
    volumes => ['/docker-registry/data:/var/lib/registry'],
    require => File['/docker-registry/data'],
  }

  file { '/opt/opencontrail_ci':
    ensure => 'directory',
    owner  => 'root',
    group  => 'root',
    mode   => '1777',
  }

  file { '/opt/opencontrail_ci/artifact_curator.py':
    ensure  => file,
    content => 'puppet:///modules/opencontrail_ci/pulp/artifact_curator.py',
    mode    => '0700',
    owner   => 'root',
    require => [
        File['/opt/opencontrail_ci']
    ],
  }

  cron { 'artifact_curator':
    command => '/opt/opencontrail_ci/artifact_curator.py',
    user    => 'root',
    hour    => '*/4',
    require => [
        File['/opt/opencontrail_ci/artifact_curator.py']
    ],
  }

}
