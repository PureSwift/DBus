"""BlueZ and NetworkManager wire API definitions for generate-service-clients.py."""


def generate_network_services(generate):
    bluez = 'https://bluez.readthedocs.io/en/latest/'
    nm = 'https://networkmanager.dev/docs/api/latest/gdbus-org.freedesktop.NetworkManager'

    def blue(name, interface, methods, properties, reference, path=None):
        generate('BlueZ', name, 'org.bluez', interface, path, methods, properties, reference)

    def network(name, suffix, methods, properties, path=None):
        generate('NetworkManager', name, 'org.freedesktop.NetworkManager',
                 'org.freedesktop.NetworkManager' + suffix, path, methods, properties,
                 nm + suffix + '.html')

    blue('BlueZ', 'org.freedesktop.DBus.ObjectManager',
         [('GetManagedObjects', [], 'a{oa{sa{sv}}}')], [],
         'https://dbus.freedesktop.org/doc/dbus-specification.html#standard-interfaces-objectmanager', '/')
    blue('BlueZAdapter', 'org.bluez.Adapter1', [
        ('StartDiscovery', [], ''), ('StopDiscovery', [], ''),
        ('RemoveDevice', [('device', 'o')], ''),
        ('SetDiscoveryFilter', [('filter', 'a{sv}')], ''),
        ('GetDiscoveryFilters', [], 'as')], [
        ('Address', 's'), ('AddressType', 's'), ('Name', 's'), ('Alias', 's', 'readwrite'),
        ('Class', 'u'), ('Powered', 'b', 'readwrite'), ('Discoverable', 'b', 'readwrite'),
        ('Pairable', 'b', 'readwrite'), ('PairableTimeout', 'u', 'readwrite'),
        ('DiscoverableTimeout', 'u', 'readwrite'), ('Discovering', 'b'), ('UUIDs', 'as'),
        ('Modalias', 's')], bluez + 'adapter-api/')
    blue('BlueZDevice', 'org.bluez.Device1', [
        (method, [], '') for method in ['Connect', 'Disconnect', 'Pair', 'CancelPairing']
    ] + [('ConnectProfile', [('uuid', 's')], ''), ('DisconnectProfile', [('uuid', 's')], '')], [
        ('Address', 's'), ('AddressType', 's'), ('Name', 's'), ('Alias', 's', 'readwrite'),
        ('Class', 'u'), ('Appearance', 'q'), ('Icon', 's'), ('Paired', 'b'),
        ('Trusted', 'b', 'readwrite'), ('Blocked', 'b', 'readwrite'), ('Connected', 'b'),
        ('Adapter', 'o'), ('UUIDs', 'as'), ('ServicesResolved', 'b'),
        ('RSSI', 'n'), ('TxPower', 'n'), ('ManufacturerData', 'a{qv}'), ('ServiceData', 'a{sv}')
    ], bluez + 'device-api/')
    blue('BlueZGattService', 'org.bluez.GattService1', [], [
        ('UUID', 's'), ('Primary', 'b'), ('Device', 'o'), ('Includes', 'ao')], bluez + 'gatt-api/')
    for name, interface, parent in [
        ('BlueZGattCharacteristic', 'org.bluez.GattCharacteristic1', 'Service'),
        ('BlueZGattDescriptor', 'org.bluez.GattDescriptor1', 'Characteristic')
    ]:
        methods = [('ReadValue', [('options', 'a{sv}')], 'ay'),
                   ('WriteValue', [('value', 'ay'), ('options', 'a{sv}')], '')]
        properties = [('UUID', 's'), (parent, 'o'), ('Value', 'ay'), ('Flags', 'as')]
        if parent == 'Service':
            methods += [('StartNotify', [], ''), ('StopNotify', [], '')]
            properties += [('Notifying', 'b')]
        blue(name, interface, methods, properties, bluez + 'gatt-api/')
    blue('BlueZGattManager', 'org.bluez.GattManager1', [
        ('RegisterApplication', [('application', 'o'), ('options', 'a{sv}')], ''),
        ('UnregisterApplication', [('application', 'o')], '')], [], bluez + 'gatt-api/')

    network('NetworkManager', '', [
        ('GetDevices', [], 'ao'), ('GetAllDevices', [], 'ao'),
        ('GetDeviceByIpIface', [('interfaceName', 's')], 'o'),
        ('ActivateConnection', [('connection', 'o'), ('device', 'o'), ('specificObject', 'o')], 'o'),
        ('AddAndActivateConnection', [('connection', 'a{sa{sv}}'), ('device', 'o'), ('specificObject', 'o')],
         [('path', 'o'), ('activeConnection', 'o')]),
        ('DeactivateConnection', [('activeConnection', 'o')], ''),
        ('Enable', [('enabled', 'b')], ''), ('Reload', [('flags', 'u')], ''),
        ('GetPermissions', [], 'a{ss}'), ('CheckConnectivity', [], 'u')], [
        ('Devices', 'ao'), ('AllDevices', 'ao'), ('NetworkingEnabled', 'b'),
        ('WirelessEnabled', 'b', 'readwrite'), ('WirelessHardwareEnabled', 'b'),
        ('ActiveConnections', 'ao'), ('PrimaryConnection', 'o'), ('ActivatingConnection', 'o'),
        ('Version', 's'), ('State', 'u'), ('Connectivity', 'u')], '/org/freedesktop/NetworkManager')
    network('NetworkManagerDevice', '.Device', [('Disconnect', [], ''), ('Delete', [], '')], [
        ('Interface', 's'), ('IpInterface', 's'), ('DeviceType', 'u'), ('State', 'u'),
        ('StateReason', '(uu)'), ('ActiveConnection', 'o'), ('AvailableConnections', 'ao'),
        ('Managed', 'b', 'readwrite'), ('Autoconnect', 'b', 'readwrite'), ('Driver', 's')])
    network('NetworkManagerWireless', '.Device.Wireless', [
        ('GetAccessPoints', [], 'ao'), ('GetAllAccessPoints', [], 'ao'),
        ('RequestScan', [('options', 'a{sv}')], '')], [
        ('HwAddress', 's'), ('PermHwAddress', 's'), ('Mode', 'u'), ('Bitrate', 'u'),
        ('AccessPoints', 'ao'), ('ActiveAccessPoint', 'o'), ('WirelessCapabilities', 'u'), ('LastScan', 'x')])
    network('NetworkManagerAccessPoint', '.AccessPoint', [], [
        ('Flags', 'u'), ('WpaFlags', 'u'), ('RsnFlags', 'u'), ('Ssid', 'ay'),
        ('Frequency', 'u'), ('HwAddress', 's'), ('Mode', 'u'), ('MaxBitrate', 'u'),
        ('Strength', 'y'), ('LastSeen', 'i')])
    network('NetworkManagerSettings', '.Settings', [
        ('ListConnections', [], 'ao'), ('GetConnectionByUuid', [('uuid', 's')], 'o'),
        ('AddConnection', [('connection', 'a{sa{sv}}')], 'o'),
        ('AddConnectionUnsaved', [('connection', 'a{sa{sv}}')], 'o'),
        ('ReloadConnections', [], 'b'), ('SaveHostname', [('hostname', 's')], '')], [
        ('Connections', 'ao'), ('Hostname', 's'), ('CanModify', 'b')],
        '/org/freedesktop/NetworkManager/Settings')
    network('NetworkManagerSettingsConnection', '.Settings.Connection', [
        ('Update', [('properties', 'a{sa{sv}}')], ''),
        ('UpdateUnsaved', [('properties', 'a{sa{sv}}')], ''),
        ('Delete', [], ''), ('GetSettings', [], 'a{sa{sv}}'),
        ('GetSecrets', [('settingName', 's')], 'a{sa{sv}}'),
        ('ClearSecrets', [], ''), ('Save', [], ''),
        ('Update2', [('settings', 'a{sa{sv}}'), ('flags', 'u'), ('args', 'a{sv}')], 'a{sv}')], [
        ('Unsaved', 'b'), ('Flags', 'u'), ('Filename', 's')])
