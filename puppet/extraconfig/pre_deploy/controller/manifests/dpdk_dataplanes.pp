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
$tenant_nic = hiera('tenant_nic')

$dpdk_tenant_port = hiera("${tenant_nic}", false)

if ! $dpdk_tenant_port { fail("Cannot find physical port name for logical port ${dpdk_tenant_port}")}

$dpdk_tenant_pci_addr = inline_template("<%= `ethtool -i ${dpdk_tenant_port} | grep bus-info | awk {'print \$2'}`.chomp %>")

if ! $dpdk_tenant_pci_addr { fail("Cannot find PCI address of ${dpdk_tenant_port}")}

if hiera('fdio_enabled', false) {
  file { "vpp dpdk_bind_lock file":
    path   => '/root/dpdk_bind_lock',
    ensure => present
  }->
  class { '::fdio::vpp':
    dpdk_pci_devs => [ $dpdk_tenant_pci_addr ],
  }

} else {
  fail ("Non FDIO dataplane unsupported on control nodes")
}