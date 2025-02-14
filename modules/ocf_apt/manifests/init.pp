class ocf_apt {
  include ocf::firewall::allow_web
  include ocf::ssl::default

  user { 'ocfapt':
    comment => 'OCF Apt',
    home    => '/opt/apt',
    shell   => '/bin/false',
  }

  package {
    [
      'nginx-full',
      'libnginx-mod-http-fancyindex',
      'reprepro',
    ]:;
  }

  file {
    default:
      owner => ocfapt,
      group => ocfapt;

    ['/opt/apt', '/opt/apt/ftp', '/opt/apt/etc', '/opt/apt/db']:
      ensure => directory,
      mode   => '0755';

    '/opt/apt/ftp/README.html':
      source => 'puppet:///modules/ocf_apt/README.html';

    '/opt/apt/etc/distributions':
      source => 'puppet:///modules/ocf_apt/distributions';

    '/opt/apt/bin':
      ensure  => directory,
      source  => 'puppet:///modules/ocf_apt/bin/',
      mode    => '0755',
      recurse => true;

    '/etc/sudoers.d/ocfdeploy-apt':
      content => "ocfdeploy ALL=(ocfapt) NOPASSWD: /opt/apt/bin/reprepro, /opt/apt/bin/include-from-stdin, /opt/apt/bin/include-changes-from-stdin\n",
      owner   => root,
      group   => root;
  }

  ocf::privatefile { '/opt/apt/etc/private.key':
    source => 'puppet:///private/apt/private.key',
    owner  => 'ocfapt',
    group  => 'ocfapt',
    mode   => '0400';
  }

  exec {
    'import-apt-gpg':
      command     => 'rm -rf /opt/apt/.gnupg && gpg --import /opt/apt/etc/private.key',
      user        => ocfapt,
      refreshonly => true,
      subscribe   => Ocf::Privatefile['/opt/apt/etc/private.key'];

    'export-gpg-pubkey':
      command => 'gpg --output /opt/apt/ftp/pubkey.gpg --export D72A0AF4',
      creates => '/opt/apt/ftp/pubkey.gpg',
      require => Exec['import-apt-gpg'];

    'initial-reprepro-export':
      command => '/opt/apt/bin/reprepro export',
      user    => ocfapt,
      creates => '/opt/apt/ftp/dists',
      require => [
        Package['reprepro'],
        File['/opt/apt/bin', '/opt/apt/etc', '/opt/apt/db', '/opt/apt/ftp'],
        Exec['import-apt-gpg'],
        User['ocfapt'],
      ];
  }
  nginx::resource::server { ['apt.ocf.berkeley.edu', 'apt']:
    listen_port      => 80,
    ssl_port         => 443,
    www_root         => '/opt/apt/ftp',
    ssl              => true,
    http2            => on,
    ssl_cert         => "/etc/ssl/private/${::fqdn}.bundle",
    ssl_key          => "/etc/ssl/private/${::fqdn}.key",
    ipv6_enable      => true,
    ipv6_listen_port => 80,
    format_log       => 'main',
    raw_append       => @(END),
      fancyindex on;
      fancyindex_exact_size off;
      END
  }
  nginx::resource::location { '=  /':
    ensure     => present,
    server     => ['apt.ocf.berkeley.edu', 'apt'],
    www_root   => '/opt/apt/ftp',
    ssl        => true,
    raw_append => @(END),
      fancyindex_header README.html;
      END
  }
  nginx::resource::location { '~  /\.(?!well-known).*':
    ensure     => present,
    server     => 'apt.ocf.berkeley.edu',
    ssl        => true,
    raw_append => @(END),
      deny all;
      END
  }
}
