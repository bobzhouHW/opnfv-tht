# Copyright 2016 Red Hat, Inc.
# All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

service { "openvswitch":
  ensure => "running",
  enable => "true",
  hasrestart => true,
  restart => '/usr/bin/systemctl restart openvswitch',
}

# Disable selinux
exec {'disable selinux':
  command => '/usr/sbin/setenforce 0',
  unless  => '/usr/sbin/getenforce | grep Permissive',
}

file_line {'selinux':
  path  => '/etc/selinux/config',
  line  => 'SELINUX=permissive',
  match => '^SELINUX=.*$',
}

file_line {'ovs_dpdk_conf':
  path => '/etc/sysconfig/openvswitch',
  line => 'DPDK_OPTIONS="-l 1,2 -n 1 --socket-mem 1024,0"',
  match => '^DPDK_OPTIONS=.*$',
}
~>
Service['openvswitch']

$dpdk_port = hiera("nic2", false)

if ! $dpdk_port { fail('Cannot find physical port name for logical port NIC2')}

$dpdk_pci_addr = inline_template("<%= `ethtool -i ${dpdk_port} | grep bus-info | awk {'print \$2'}` %>")

if ! $dpdk_pci_addr { fail("Cannot find PCI address of ${dpdk_port}")}

$dpdk_bind_type = hiera("dpdk_pmd_type")
exec {'bind_dpdk_port':
  command  => "dpdk_nic_bind --force --bind=${dpdk_bind_type} ${dpdk_pci_addr}",
  path     => "/usr/sbin/",
  creates  => '/root/dpdk_bind_lock'
}
->
file {'/root/dpdk_bind_lock':
  ensure => present
}

exec {'set ovs bridge datapath':
  command => 'ovs-vsctl set bridge br-phy datapath_type=netdev',
  unless  => 'ovs-vsctl list bridge br-phy | grep datapath_type | grep netdev',
  path    => '/usr/sbin:/usr/bin:/sbin:/bin',
  require => [ Exec['bind_dpdk_port'], Service['openvswitch'] ]
}
->
exec { 'add dpdk port to ovs':
  command => 'ovs-vsctl add-port br-phy dpdk0 -- set Interface dpdk0 type=dpdk',
  unless  => 'ovs-vsctl list-ports br-phy | grep dpdk0',
  path    => '/usr/sbin:/usr/bin:/sbin:/bin',
}
->
exec { 'br-phy patch port':
  command => 'ovs-vsctl add-port br-phy patch-br-phy -- set Interface patch-br-phy type=patch options:peer=patch-br-tun',
  unless  => 'ovs-vsctl list-ports br-phy | grep patch-br-phy',
  path    => '/usr/sbin:/usr/bin:/sbin:/bin',
}
->
exec { 'br-tun patch port':
  command => 'ovs-vsctl add-port br-tun patch-br-tun -- set Interface patch-br-tun type=patch options:peer=patch-br-phy',
  unless  => 'ovs-vsctl list-ports br-tun | grep patch-br-tun',
  path    => '/usr/sbin:/usr/bin:/sbin:/bin',
}

