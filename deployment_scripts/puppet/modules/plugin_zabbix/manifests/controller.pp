#
#    Copyright 2015 Mirantis, Inc.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.
#
class plugin_zabbix::controller {

  include plugin_zabbix::params

  file { '/etc/dbconfig-common':
    ensure    => directory,
    owner     => 'root',
    group     => 'root',
    mode      => '0755',
  }

  file { '/etc/dbconfig-common/zabbix-server-mysql.conf':
    ensure    => present,
    require   => File['/etc/dbconfig-common'],
    mode      => '0600',
    source    => 'puppet:///modules/plugin_zabbix/zabbix-server-mysql.conf',
  }

  package { $plugin_zabbix::params::server_pkg:
    ensure    => present,
    require   => File['/etc/dbconfig-common/zabbix-server-mysql.conf'],
  }

  file { $plugin_zabbix::params::server_config:
    ensure    => present,
    require   => Package[$plugin_zabbix::params::server_pkg],
    content   => template($plugin_zabbix::params::server_config_template),
  }

  file { $plugin_zabbix::params::server_scripts:
    ensure    => directory,
    require   => Package[$plugin_zabbix::params::server_pkg],
    recurse   => true,
    purge     => true,
    force     => true,
    mode      => '0755',
    source    => 'puppet:///modules/plugin_zabbix/externalscripts',
  }

  file { 'zabbix-server-ocf' :
    ensure      => present,
    path        => "${plugin_zabbix::params::ocf_scripts_dir}/${plugin_zabbix::params::ocf_scripts_provider}/${plugin_zabbix::params::server_service}",
    mode        => '0755',
    owner       => 'root',
    group       => 'root',
    source      => 'puppet:///modules/plugin_zabbix/zabbix-server.ocf',
  }
  service { "${plugin_zabbix::params::server_service}-init-stopped":
    ensure      => 'stopped',
    name        => $plugin_zabbix::params::server_service,
    enable      => false,
    require     => File[$plugin_zabbix::params::server_config],
  }
  service { "${plugin_zabbix::params::server_service}-started":
    ensure    => running,
    name      => "p_${plugin_zabbix::params::server_service}",
    enable    => true,
    provider  => 'pacemaker',
  }
  service { "vip__${plugin_zabbix::params::server_service}-started":
    ensure    => running,
    name      => "vip__${plugin_zabbix::params::server_service}",
    enable    => true,
    provider  => 'pacemaker',
  }

  Service["vip__${plugin_zabbix::params::server_service}-started"] -> Service["${plugin_zabbix::params::server_service}-started"]
  File['zabbix-server-ocf'] -> Service["${plugin_zabbix::params::server_service}-init-stopped"] -> Service["${plugin_zabbix::params::server_service}-started"]

  cron { 'zabbix db_clean':
    ensure      => 'present',
    require     => File[$plugin_zabbix::params::server_scripts],
    command     => "${plugin_zabbix::params::server_scripts}/db_clean.sh",
    user        => 'root',
    minute      => '*/5',
  }

  plugin_zabbix::db::mysql_db { $plugin_zabbix::params::db_name:
    user     => $plugin_zabbix::params::db_user,
    password => $plugin_zabbix::params::db_password,
    host     => $plugin_zabbix::params::db_ip,
  }

  if $plugin_zabbix::params::frontend {
    class { 'plugin_zabbix::frontend':
      require   => File[$plugin_zabbix::params::server_config],
      before    => Class['plugin_zabbix::ha::haproxy'],
    }
  }

  include plugin_zabbix::ha::haproxy

  firewall { '998 zabbix agent vip':
    proto     => 'tcp',
    action    => 'accept',
    port      => $plugin_zabbix::params::zabbix_ports['agent'],
  }

  firewall { '998 zabbix server vip':
    proto     => 'tcp',
    action    => 'accept',
    port      => $plugin_zabbix::params::zabbix_ports['server'],
  }

}