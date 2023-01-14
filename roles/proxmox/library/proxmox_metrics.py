#!/usr/bin/python
# -*- coding: utf-8 -*-

ANSIBLE_METADATA = {
    'metadata_version': '0.1',
    'status': ['preview'],
    'supported_by': 'dazzathewiz'
}

DOCUMENTATION = '''
---
module: proxmox_metrics

short_description: Manages metric server in Proxmox https://pve.proxmox.com/pve-docs/pve-admin-guide.html#external_metric_server

options:
    name:
        required: true
        aliases: [ "id", "serverid" ]
        description:
            - Name of the metric server entry.
    port:
        required: true
        type: int
        description:
            - Server network port.
    server:
        required: true
        description:
            - Server DNS name or IP address.
    type:
        required: true
        aliases: [ "metrictype" ]
        choices: [ "graphite", "influxdb" ]
        description:
            - Type of plugin, must be supported by Proxmox.
    state:
        required: false
        default: "present"
        choices: [ "present", "absent" ]
        description:
            - Specifies whether the metric server should exist or not.
    disable:
        required: false
        default: yes
        type: bool
        description:
            - Whether or not the metric server should be enabled in PVE.
    bucket:
        required: false
        description:
            - Optionally sets the InfluxDB bucket/db. Only necessary when 
              using the HTTP v2 api.
    influxdbproto:
        required: false
        default: udp
        choices: [ "udp", "http", "https" ]
        description:
            - Optionally sets the InfluxDB protocol.
    maxbodysize:
        required: false
        default: 25000000
        type: int
        description:
            - Optionally sets InfluxDB max-body-size in bytes. Requests are
              batched up to this size.
    mtu:
        required: false
        default: 1500
        type: int
        description:
            - Optionally sets MTU for metrics transmission over UDP.
    organization:
        required: false
        description:
            - The InfluxDB organization. Only necessary when using the http v2 api.
              Has no meaning using v2 compatibility api.
    path:
        required: false
        description:
            - The root graphite path (ex: proxmox.mycluster.mykey)
    proto:
        required: false
        choices: [ "udp", "tcp" ]
        description:
            - Protocol to send graphite data. TCP or UDP.
    timeout:
        required: false
        default: 1
        type: int
        description:
            - Optionally set graphite TCP socket timeout (default=1)
    token:
        required: false
        description:
            - The InfluxDB access token. Only necessary when using the http v2 api.
              if the v2 compatibility api is used, use 'user:password' instead.
    verifycertificate:
        required: false
        default: yes
        type: boolean
        description:
            - Set to no to disable certificate verification for https endpoints.

author:
    - Darren Ehrlich (@dazzathewiz)
'''

EXAMPLES = '''
- name: Create InfluxDB metrics server
  proxmox_metrics:
    name: InfluxDB
    type: influxdb
    server: 192.168.0.10
    port: 8086
    influxdbproto: http
    organization: my.homelab
    bucket: proxmox
'''

RETURN = '''
'''

from ansible.module_utils.basic import AnsibleModule
from ansible.module_utils._text import to_text
from ansible.module_utils.pvesh import ProxmoxShellError
import ansible.module_utils.pvesh as pvesh

class ProxmoxMetricServer(object):
    def __init__(self, module):
        self.module = module
        self.name = module.params['name']
        self.port = module.params['port']
        self.server = module.params['server']
        self.state = module.params['state']
        self.type = module.params['type']
        self.disable = module.params['disable']
        self.bucket = module.params['bucket']
        self.influxdbproto = module.params['influxdbproto']
        self.maxbodysize = module.params['maxbodysize']
        self.mtu = module.params['mtu']
        self.organization = module.params['organization']
        self.path = module.params['path']
        self.proto = module.params['proto']
        self.timeout = module.params['timeout']
        self.token = module.params['token']
        self.verifycertificate = module.params['verifycertificate']
        self.updatetoken = module.params['updatetoken']

        try:
            self.existing_metric_servers = pvesh.get("cluster/metrics/server/")
        except ProxmoxShellError as e:
            self.module.fail_json(msg=e.message, status_code=e.status_code)

    def lookup(self):
        for item in self.existing_metric_servers:
            if item['id'] == self.name:
                try:
                    return pvesh.get("cluster/metrics/server/{}".format(item['id'])) | item
                except ProxmoxShellError as e:
                    self.module.fail_json(msg=e.message, status_code=e.status_code)
        return None
    
    def exists(self):
        for item in self.existing_metric_servers:
            if item["id"] == self.name:
                return True
        return False
    
    def prepare_metric_server_args(self):
        args = {}

        args['port'] = self.port
        args['server'] = self.server
        args['type'] = self.type

        if self.disable is not None:
            args['disable'] = self.disable
        else:
            args['disable'] = False
        if self.bucket is not None:
            args['bucket'] = self.bucket
        if self.influxdbproto is not None:
            args['influxdbproto'] = self.influxdbproto
        if self.maxbodysize is not None:
            args['max-body-size'] = self.maxbodysize
        if self.mtu is not None:
            args['mtu'] = self.mtu
        if self.organization is not None:
            args['organization'] = self.organization
        if self.path is not None:
            args['path'] = self.path
        if self.proto is not None:
            args['proto'] = self.proto
        if self.timeout is not None:
            args['timeout'] = self.timeout
        if self.token is not None:
            args['token'] = self.token
        if self.verifycertificate is not None:
            args['verify-certificate'] = self.verifycertificate
        
        return args

    def create_metric_server(self):
        new_metric_server = self.prepare_metric_server_args()
        try:
            pvesh.create("cluster/metrics/server/{}".format(self.name), **new_metric_server)
            return None
        except ProxmoxShellError as e:
            return e.message

    def modify_metric_server(self):
        lookup = self.lookup()
        new_metric_server = self.prepare_metric_server_args()

        staged_metric_server = {}
        updated_fields = []
        error = None
        
        for key in new_metric_server:
            new_value = to_text(new_metric_server[key]) if isinstance(new_metric_server[key], str) else new_metric_server[key]

            if key not in lookup or new_value != lookup[key]:
                # Current token isn't available in API, so implement hack for idempotentcy
                if key == 'token' and not self.updatetoken:
                    continue
                updated_fields.append(key)
                staged_metric_server[key] = new_metric_server[key]
                continue
            if key == 'port' or key == 'server':
                staged_metric_server[key] = new_metric_server[key]

        if self.module.check_mode:
            self.module.exit_json(changed=bool(updated_fields), expected_changes=updated_fields)

        if not updated_fields:
            # No changes necessary
            return (updated_fields, error)

        try:
            pvesh.set("cluster/metrics/server/{}".format(self.name), **staged_metric_server)
        except ProxmoxShellError as e:
            error = e.message

        return (updated_fields, error)

    def remove_metric_server(self):
        try:
            pvesh.delete("cluster/metrics/server/{}".format(self.name))
            return (True, None)
        except ProxmoxShellError as e:
            return (False, e.message)

def main():
    # Refer to https://pve.proxmox.com/pve-docs/api-viewer/index.html
    module = AnsibleModule(
        argument_spec = dict(
            name=dict(type='str', required=True, aliases=['id', 'serverid']),
            port=dict(type='int', required=True),
            server=dict(type='str', required=True),
            type=dict(default=None, type='str', required=True, aliases=['metrictype'],
                        choices=["graphite", "influxdb"]),
            state=dict(default='present', choices=['present', 'absent'], type='str'),
            disable=dict(required=False, type='bool', default=False),
            bucket=dict(default=None, type='str', required=False),
            influxdbproto=dict(default=None, type='str', required=False,
                        choices=["udp", "http", "https"]),
            maxbodysize=dict(default=None, type='int', required=False),
            mtu=dict(default=None, type='int', required=False),
            organization=dict(default=None, required=False, type='str'),
            path=dict(default=None, required=False, type='str'),
            proto=dict(default=None, type='str', required=False,
                        choices=["udp", "tcp"]),
            timeout=dict(default=None, type='int', required=False),
            token=dict(default=None, required=False, type='str'),
            verifycertificate=dict(default=None, required=False, type='bool'),
            updatetoken=dict(default=False, required=False, type='bool'),
        ),
        supports_check_mode=True
    )

    metricserver = ProxmoxMetricServer(module)

    error = None
    result = {}
    result['state'] = metricserver.state
    result['changed'] = False

    if metricserver.state == 'absent':
        if metricserver.exists():
            result['changed'] = True
            if module.check_mode:
                module.exit_json(**result)
            (changed, error) = metricserver.remove_metric_server()
    elif metricserver.state == 'present':
        if not metricserver.exists():
            result['changed'] = True
            if module.check_mode:
                module.exit_json(**result)

            error = metricserver.create_metric_server()
        else:
            # modify metricserver (check mode is ok)
            (updated_fields,error) = metricserver.modify_metric_server()

            if updated_fields:
                result['changed'] = True
                result['updated_fields'] = updated_fields

    if error is not None:
        module.fail_json(name=metricserver.name, msg=error)

    module.exit_json(**result)

if __name__ == '__main__':
    main()
