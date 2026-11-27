"""Wire API definitions for all generated D-Bus service clients.

Each function passes interface metadata to the supplied generator. Importing this
module does not generate files.
"""


def generate_services(generate):
    """Emit every supported service interface through the supplied callback."""
    _define_upower(generate)
    _define_login1(generate)
    _define_screensaver(generate)
    _define_network_services(generate)
    _define_remaining_services(generate)
    _define_media_and_agents(generate)


def _define_upower(generate):
    generate('UPower', 'UPower', 'org.freedesktop.UPower', 'org.freedesktop.UPower',
             '/org/freedesktop/UPower', [
                 ('EnumerateDevices', [], 'ao'), ('EnumerateKbdBacklights', [], 'ao'),
                 ('GetDisplayDevice', [], 'o'), ('GetCriticalAction', [], 's')],
             [('DaemonVersion', 's'), ('OnBattery', 'b'), ('LidIsClosed', 'b'), ('LidIsPresent', 'b')],
             'https://upower.freedesktop.org/docs/UPower.html')

    generate('UPower', 'UPowerDevice', 'org.freedesktop.UPower', 'org.freedesktop.UPower.Device',
             None, [('Refresh', [], ''),
                    ('GetHistory', [('type', 's'), ('timespan', 'u'), ('resolution', 'u')], 'a(udu)'),
                    ('GetStatistics', [('type', 's')], 'a(dd)'),
                    ('EnableChargeThreshold', [('enabled', 'b')], '')],
             [(name, sig) for sig, names in [
                 ('s', 'NativePath Vendor Model Serial IconName CapacityLevel'),
                 ('t', 'UpdateTime'),
                 ('u', 'Type State Technology WarningLevel BatteryLevel ChargeStartThreshold ChargeEndThreshold ChargeThresholdSettingsSupported'),
                 ('b', 'PowerSupply HasHistory HasStatistics Online IsPresent IsRechargeable ChargeThresholdEnabled ChargeThresholdSupported'),
                 ('d', 'Energy EnergyEmpty EnergyFull EnergyFullDesign EnergyRate Voltage Luminosity Percentage Temperature Capacity VoltageMinDesign VoltageMaxDesign'),
                 ('i', 'ChargeCycles'), ('x', 'TimeToEmpty TimeToFull')]
              for name in names.split()], 'https://upower.freedesktop.org/docs/Device.html')


def _define_login1(generate):
    login_methods = [
        ('GetSession', [('sessionID', 's')], 'o'), ('GetSessionByPID', [('pid', 'u')], 'o'),
        ('GetUser', [('uid', 'u')], 'o'), ('GetUserByPID', [('pid', 'u')], 'o'),
        ('GetSeat', [('seatID', 's')], 'o'), ('ListSessions', [], 'a(susso)'),
        ('ListUsers', [], 'a(uso)'), ('ListSeats', [], 'a(so)'), ('ListInhibitors', [], 'a(ssssuu)'),
        ('Inhibit', [('what', 's'), ('who', 's'), ('why', 's'), ('mode', 's')], 'h'),
        ('LockSessions', [], ''), ('UnlockSessions', [], ''),
        ('ScheduleShutdown', [('type', 's'), ('usec', 't')], ''),
        ('CancelScheduledShutdown', [], 'b'),
    ]
    for action in ['Release', 'Activate', 'Lock', 'Unlock', 'Terminate']:
        login_methods.append((action + 'Session', [('sessionID', 's')], ''))
    for action in ['PowerOff', 'Reboot', 'Halt', 'Suspend', 'Hibernate', 'HybridSleep', 'SuspendThenHibernate']:
        login_methods += [(action, [('interactive', 'b')], ''), ('Can' + action, [], 's')]
    generate('Login1', 'Login1', 'org.freedesktop.login1', 'org.freedesktop.login1.Manager',
             '/org/freedesktop/login1', login_methods,
             [('PreparingForSleep', 'b'), ('PreparingForShutdown', 'b'), ('IdleHint', 'b'),
              ('IdleSinceHint', 't'), ('BlockInhibited', 's'), ('DelayInhibited', 's'),
              ('InhibitDelayMaxUSec', 't'), ('LidClosed', 'b'), ('Docked', 'b')],
             'https://www.freedesktop.org/software/systemd/man/latest/org.freedesktop.login1.html')

    generate('Login1', 'Login1Session', 'org.freedesktop.login1', 'org.freedesktop.login1.Session',
             None, [(method, [], '') for method in ['Activate', 'Lock', 'Unlock', 'Terminate']] +
             [('SetIdleHint', [('idle', 'b')], ''), ('SetLockedHint', [('locked', 'b')], '')],
             [('Id', 's'), ('Name', 's'), ('Type', 's'), ('Class', 's'), ('State', 's'),
              ('Active', 'b'), ('Remote', 'b'), ('IdleHint', 'b'), ('LockedHint', 'b')],
             'https://www.freedesktop.org/software/systemd/man/latest/org.freedesktop.login1.html')


def _define_screensaver(generate):
    generate('ScreenSaver', 'ScreenSaver', 'org.freedesktop.ScreenSaver', 'org.freedesktop.ScreenSaver',
             '/org/freedesktop/ScreenSaver', [
                 ('Inhibit', [('applicationName', 's'), ('reason', 's')], 'u'),
                 ('UnInhibit', [('cookie', 'u')], ''), ('Lock', [], ''),
                 ('SimulateUserActivity', [], ''), ('GetActive', [], 'b'),
                 ('GetActiveTime', [], 'u'), ('GetSessionIdleTime', [], 'u'),
                 ('SetActive', [('active', 'b')], 'b'),
                 ('Throttle', [('applicationName', 's'), ('reason', 's')], 'u'),
                 ('UnThrottle', [('cookie', 'u')], '')], [],
             'https://specifications.freedesktop.org/idle-inhibit/latest/ ; '
             'https://github.com/KDE/kscreenlocker/blob/master/dbus/org.freedesktop.ScreenSaver.xml', 'session')


def _define_network_services(generate):
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


def _define_remaining_services(generate):
    """Standard interface signatures transcribed from the linked upstream XML."""
    generate('Avahi', 'Avahi', 'org.freedesktop.Avahi', 'org.freedesktop.Avahi.Server', '/', [
        ('GetVersionString', [], 's'),
        ('GetAPIVersion', [], 'u'),
        ('GetHostName', [], 's'),
        ('SetHostName', [('name', 's')], ''),
        ('GetHostNameFqdn', [], 's'),
        ('GetDomainName', [], 's'),
        ('IsNSSSupportAvailable', [], 'b'),
        ('GetState', [], 'i'),
        ('GetLocalServiceCookie', [], 'u'),
        ('GetAlternativeHostName', [('name', 's')], 's'),
        ('GetAlternativeServiceName', [('name', 's')], 's'),
        ('GetNetworkInterfaceNameByIndex', [('index', 'i')], 's'),
        ('GetNetworkInterfaceIndexByName', [('name', 's')], 'i'),
        ('ResolveHostName', [('interfaceIndex', 'i'), ('protocolIndex', 'i'), ('name', 's'), ('aprotocol', 'i'), ('flags', 'u')], [('interfaceIndex', 'i'), ('protocolIndex', 'i'), ('name', 's'), ('aprotocol', 'i'), ('address', 's'), ('flags', 'u')]),
        ('ResolveAddress', [('interfaceIndex', 'i'), ('protocolIndex', 'i'), ('address', 's'), ('flags', 'u')], [('interfaceIndex', 'i'), ('protocolIndex', 'i'), ('aprotocol', 'i'), ('address', 's'), ('name', 's'), ('flags', 'u')]),
        ('ResolveService', [('interfaceIndex', 'i'), ('protocolIndex', 'i'), ('name', 's'), ('type', 's'), ('domain', 's'), ('aprotocol', 'i'), ('flags', 'u')], [('interfaceIndex', 'i'), ('protocolIndex', 'i'), ('name', 's'), ('type', 's'), ('domain', 's'), ('host', 's'), ('aprotocol', 'i'), ('address', 's'), ('port', 'q'), ('txt', 'aay'), ('flags', 'u')]),
        ('EntryGroupNew', [], 'o'),
        ('DomainBrowserNew', [('interfaceIndex', 'i'), ('protocolIndex', 'i'), ('domain', 's'), ('btype', 'i'), ('flags', 'u')], 'o'),
        ('ServiceTypeBrowserNew', [('interfaceIndex', 'i'), ('protocolIndex', 'i'), ('domain', 's'), ('flags', 'u')], 'o'),
        ('ServiceBrowserNew', [('interfaceIndex', 'i'), ('protocolIndex', 'i'), ('type', 's'), ('domain', 's'), ('flags', 'u')], 'o'),
        ('ServiceResolverNew', [('interfaceIndex', 'i'), ('protocolIndex', 'i'), ('name', 's'), ('type', 's'), ('domain', 's'), ('aprotocol', 'i'), ('flags', 'u')], 'o'),
        ('HostNameResolverNew', [('interfaceIndex', 'i'), ('protocolIndex', 'i'), ('name', 's'), ('aprotocol', 'i'), ('flags', 'u')], 'o'),
        ('AddressResolverNew', [('interfaceIndex', 'i'), ('protocolIndex', 'i'), ('address', 's'), ('flags', 'u')], 'o'),
        ('RecordBrowserNew', [('interfaceIndex', 'i'), ('protocolIndex', 'i'), ('name', 's'), ('clazz', 'q'), ('type', 'q'), ('flags', 'u')], 'o'),
    ], [
    ], 'https://raw.githubusercontent.com/avahi/avahi/master/avahi-daemon/org.freedesktop.Avahi.Server.xml', bus='system', swift_name='Avahi.Server')
    generate('Avahi', 'AvahiServer2', 'org.freedesktop.Avahi', 'org.freedesktop.Avahi.Server2', '/', [
        ('GetVersionString', [], 's'),
        ('GetAPIVersion', [], 'u'),
        ('GetHostName', [], 's'),
        ('SetHostName', [('name', 's')], ''),
        ('GetHostNameFqdn', [], 's'),
        ('GetDomainName', [], 's'),
        ('IsNSSSupportAvailable', [], 'b'),
        ('GetState', [], 'i'),
        ('GetLocalServiceCookie', [], 'u'),
        ('GetAlternativeHostName', [('name', 's')], 's'),
        ('GetAlternativeServiceName', [('name', 's')], 's'),
        ('GetNetworkInterfaceNameByIndex', [('index', 'i')], 's'),
        ('GetNetworkInterfaceIndexByName', [('name', 's')], 'i'),
        ('ResolveHostName', [('interfaceIndex', 'i'), ('protocolIndex', 'i'), ('name', 's'), ('aprotocol', 'i'), ('flags', 'u')], [('interfaceIndex', 'i'), ('protocolIndex', 'i'), ('name', 's'), ('aprotocol', 'i'), ('address', 's'), ('flags', 'u')]),
        ('ResolveAddress', [('interfaceIndex', 'i'), ('protocolIndex', 'i'), ('address', 's'), ('flags', 'u')], [('interfaceIndex', 'i'), ('protocolIndex', 'i'), ('aprotocol', 'i'), ('address', 's'), ('name', 's'), ('flags', 'u')]),
        ('ResolveService', [('interfaceIndex', 'i'), ('protocolIndex', 'i'), ('name', 's'), ('type', 's'), ('domain', 's'), ('aprotocol', 'i'), ('flags', 'u')], [('interfaceIndex', 'i'), ('protocolIndex', 'i'), ('name', 's'), ('type', 's'), ('domain', 's'), ('host', 's'), ('aprotocol', 'i'), ('address', 's'), ('port', 'q'), ('txt', 'aay'), ('flags', 'u')]),
        ('EntryGroupNew', [], 'o'),
        ('DomainBrowserPrepare', [('interfaceIndex', 'i'), ('protocolIndex', 'i'), ('domain', 's'), ('btype', 'i'), ('flags', 'u')], 'o'),
        ('ServiceTypeBrowserPrepare', [('interfaceIndex', 'i'), ('protocolIndex', 'i'), ('domain', 's'), ('flags', 'u')], 'o'),
        ('ServiceBrowserPrepare', [('interfaceIndex', 'i'), ('protocolIndex', 'i'), ('type', 's'), ('domain', 's'), ('flags', 'u')], 'o'),
        ('ServiceResolverPrepare', [('interfaceIndex', 'i'), ('protocolIndex', 'i'), ('name', 's'), ('type', 's'), ('domain', 's'), ('aprotocol', 'i'), ('flags', 'u')], 'o'),
        ('HostNameResolverPrepare', [('interfaceIndex', 'i'), ('protocolIndex', 'i'), ('name', 's'), ('aprotocol', 'i'), ('flags', 'u')], 'o'),
        ('AddressResolverPrepare', [('interfaceIndex', 'i'), ('protocolIndex', 'i'), ('address', 's'), ('flags', 'u')], 'o'),
        ('RecordBrowserPrepare', [('interfaceIndex', 'i'), ('protocolIndex', 'i'), ('name', 's'), ('clazz', 'q'), ('type', 'q'), ('flags', 'u')], 'o'),
    ], [
    ], 'https://raw.githubusercontent.com/avahi/avahi/master/avahi-daemon/org.freedesktop.Avahi.Server.xml', bus='system', swift_name='Avahi.Server2')
    generate('Avahi', 'AvahiEntryGroup', 'org.freedesktop.Avahi', 'org.freedesktop.Avahi.EntryGroup', None, [
        ('Free', [], ''),
        ('Commit', [], ''),
        ('Reset', [], ''),
        ('GetState', [], 'i'),
        ('IsEmpty', [], 'b'),
        ('AddService', [('interfaceIndex', 'i'), ('protocolIndex', 'i'), ('flags', 'u'), ('name', 's'), ('type', 's'), ('domain', 's'), ('host', 's'), ('port', 'q'), ('txt', 'aay')], ''),
        ('AddServiceSubtype', [('interfaceIndex', 'i'), ('protocolIndex', 'i'), ('flags', 'u'), ('name', 's'), ('type', 's'), ('domain', 's'), ('subtype', 's')], ''),
        ('UpdateServiceTxt', [('interfaceIndex', 'i'), ('protocolIndex', 'i'), ('flags', 'u'), ('name', 's'), ('type', 's'), ('domain', 's'), ('txt', 'aay')], ''),
        ('AddAddress', [('interfaceIndex', 'i'), ('protocolIndex', 'i'), ('flags', 'u'), ('name', 's'), ('address', 's')], ''),
        ('AddRecord', [('interfaceIndex', 'i'), ('protocolIndex', 'i'), ('flags', 'u'), ('name', 's'), ('clazz', 'q'), ('type', 'q'), ('ttl', 'u'), ('rdata', 'ay')], ''),
    ], [
    ], 'https://raw.githubusercontent.com/avahi/avahi/master/avahi-daemon/org.freedesktop.Avahi.EntryGroup.xml', bus='system', swift_name='Avahi.EntryGroup')
    generate('Avahi', 'AvahiServiceBrowser', 'org.freedesktop.Avahi', 'org.freedesktop.Avahi.ServiceBrowser', None, [
        ('Free', [], ''),
        ('Start', [], ''),
    ], [
    ], 'https://raw.githubusercontent.com/avahi/avahi/master/avahi-daemon/org.freedesktop.Avahi.ServiceBrowser.xml', bus='system', swift_name='Avahi.ServiceBrowser')
    generate('Avahi', 'AvahiServiceResolver', 'org.freedesktop.Avahi', 'org.freedesktop.Avahi.ServiceResolver', None, [
        ('Free', [], ''),
        ('Start', [], ''),
    ], [
    ], 'https://raw.githubusercontent.com/avahi/avahi/master/avahi-daemon/org.freedesktop.Avahi.ServiceResolver.xml', bus='system', swift_name='Avahi.ServiceResolver')
    generate('SecretService', 'SecretService', 'org.freedesktop.secrets', 'org.freedesktop.Secret.Service', '/org/freedesktop/secrets', [
        ('OpenSession', [('algorithm', 's'), ('input', 'v')], [('output', 'v'), ('result', 'o')]),
        ('CreateCollection', [('properties', 'a{sv}'), ('alias', 's')], [('collection', 'o'), ('prompt', 'o')]),
        ('SearchItems', [('attributes', 'a{ss}')], [('unlocked', 'ao'), ('locked', 'ao')]),
        ('Unlock', [('objects', 'ao')], [('unlocked', 'ao'), ('prompt', 'o')]),
        ('Lock', [('objects', 'ao')], [('locked', 'ao'), ('prompt', 'o')]),
        ('GetSecrets', [('items', 'ao'), ('session', 'o')], 'a{o(oayays)}'),
        ('ReadAlias', [('name', 's')], 'o'),
        ('SetAlias', [('name', 's'), ('collection', 'o')], ''),
    ], [
        ('Collections', 'ao'),
    ], 'https://raw.githubusercontent.com/GNOME/libsecret/main/libsecret/org.freedesktop.Secrets.xml', bus='session', swift_name='SecretService.Service')
    generate('SecretService', 'SecretServiceCollection', 'org.freedesktop.secrets', 'org.freedesktop.Secret.Collection', None, [
        ('Delete', [], 'o'),
        ('SearchItems', [('attributes', 'a{ss}')], 'ao'),
        ('CreateItem', [('properties', 'a{sv}'), ('secret', '(oayays)'), ('replace', 'b')], [('item', 'o'), ('prompt', 'o')]),
    ], [
        ('Items', 'ao'),
        ('Label', 's', 'readwrite'),
        ('Locked', 'b'),
        ('Created', 't'),
        ('Modified', 't'),
    ], 'https://raw.githubusercontent.com/GNOME/libsecret/main/libsecret/org.freedesktop.Secrets.xml', bus='session', swift_name='SecretService.Collection')
    generate('SecretService', 'SecretServiceItem', 'org.freedesktop.secrets', 'org.freedesktop.Secret.Item', None, [
        ('Delete', [], 'o'),
        ('GetSecret', [('session', 'o')], '(oayays)'),
        ('SetSecret', [('secret', '(oayays)')], ''),
    ], [
        ('Locked', 'b'),
        ('Attributes', 'a{ss}', 'readwrite'),
        ('Label', 's', 'readwrite'),
        ('Created', 't'),
        ('Modified', 't'),
    ], 'https://raw.githubusercontent.com/GNOME/libsecret/main/libsecret/org.freedesktop.Secrets.xml', bus='session', swift_name='SecretService.Item')
    generate('SecretService', 'SecretServiceSession', 'org.freedesktop.secrets', 'org.freedesktop.Secret.Session', None, [
        ('Close', [], ''),
    ], [
    ], 'https://raw.githubusercontent.com/GNOME/libsecret/main/libsecret/org.freedesktop.Secrets.xml', bus='session', swift_name='SecretService.Session')
    generate('SecretService', 'SecretServicePrompt', 'org.freedesktop.secrets', 'org.freedesktop.Secret.Prompt', None, [
        ('Prompt', [('windowId', 's')], ''),
        ('Dismiss', [], ''),
    ], [
    ], 'https://raw.githubusercontent.com/GNOME/libsecret/main/libsecret/org.freedesktop.Secrets.xml', bus='session', swift_name='SecretService.Prompt')
    generate('DesktopNotifications', 'DesktopNotifications', 'org.freedesktop.Notifications', 'org.freedesktop.Notifications', '/org/freedesktop/Notifications', [
        ('Notify', [('appName', 's'), ('replacesId', 'u'), ('appIcon', 's'), ('summary', 's'), ('body', 's'), ('actions', 'as'), ('hints', 'a{sv}'), ('timeout', 'i')], 'u'),
        ('CloseNotification', [('id', 'u')], ''),
        ('GetCapabilities', [], 'as'),
        ('GetServerInformation', [], [('name', 's'), ('vendor', 's'), ('version', 's'), ('specVersion', 's')]),
        ('Inhibit', [('desktopEntry', 's'), ('reason', 's'), ('hints', 'a{sv}')], 'u'),
        ('UnInhibit', [('argument0', 'u')], ''),
    ], [
        ('Inhibited', 'b'),
    ], 'https://raw.githubusercontent.com/KDE/knotifications/master/src/org.freedesktop.Notifications.xml', bus='session', swift_name='DesktopNotifications')
    generate('StatusNotifier', 'StatusNotifier', 'org.kde.StatusNotifierWatcher', 'org.kde.StatusNotifierWatcher', '/StatusNotifierWatcher', [
        ('RegisterStatusNotifierItem', [('service', 's')], ''),
        ('RegisterStatusNotifierHost', [('service', 's')], ''),
    ], [
        ('RegisteredStatusNotifierItems', 'as'),
        ('IsStatusNotifierHostRegistered', 'b'),
        ('ProtocolVersion', 'i'),
    ], 'https://raw.githubusercontent.com/KDE/kstatusnotifieritem/master/src/org.kde.StatusNotifierWatcher.xml', bus='session', swift_name='StatusNotifier.Watcher')
    generate('StatusNotifier', 'StatusNotifierItem', None, 'org.kde.StatusNotifierItem', '/StatusNotifierItem', [
        ('ProvideXdgActivationToken', [('token', 's')], ''),
        ('ContextMenu', [('x', 'i'), ('y', 'i')], ''),
        ('Activate', [('x', 'i'), ('y', 'i')], ''),
        ('SecondaryActivate', [('x', 'i'), ('y', 'i')], ''),
        ('Scroll', [('delta', 'i'), ('orientation', 's')], ''),
    ], [
        ('Category', 's'),
        ('Id', 's'),
        ('Title', 's'),
        ('Status', 's'),
        ('WindowId', 'i'),
        ('IconThemePath', 's'),
        ('Menu', 'o'),
        ('ItemIsMenu', 'b'),
        ('IconName', 's'),
        ('IconPixmap', 'a(iiay)'),
        ('OverlayIconName', 's'),
        ('OverlayIconPixmap', 'a(iiay)'),
        ('AttentionIconName', 's'),
        ('AttentionIconPixmap', 'a(iiay)'),
        ('AttentionMovieName', 's'),
        ('ToolTip', '(sa(iiay)ss)'),
    ], 'https://raw.githubusercontent.com/KDE/kstatusnotifieritem/master/src/org.kde.StatusNotifierItem.xml', bus='session', swift_name='StatusNotifier.Item')
    generate('StatusNotifier', 'StatusNotifierMenu', None, 'com.canonical.dbusmenu', None, [
        ('GetLayout', [('parentId', 'i'), ('recursionDepth', 'i'), ('propertyNames', 'as')], [('revision', 'u'), ('layout', '(ia{sv}av)')]),
        ('GetGroupProperties', [('ids', 'ai'), ('propertyNames', 'as')], 'a(ia{sv})'),
        ('GetProperty', [('id', 'i'), ('name', 's')], 'v'),
        ('Event', [('id', 'i'), ('eventId', 's'), ('data', 'v'), ('timestamp', 'u')], ''),
        ('EventGroup', [('events', 'a(isvu)')], 'ai'),
        ('AboutToShow', [('id', 'i')], 'b'),
        ('AboutToShowGroup', [('ids', 'ai')], [('updatesNeeded', 'ai'), ('idErrors', 'ai')]),
    ], [
        ('Version', 'u'),
        ('TextDirection', 's'),
        ('Status', 's'),
        ('IconThemePath', 'as'),
    ], 'https://raw.githubusercontent.com/JetBrains/libdbusmenu/master/libdbusmenu-glib/dbus-menu.xml', bus='session', swift_name='StatusNotifier.Menu')
    generate('FreedesktopPortal', 'FreedesktopPortal', 'org.freedesktop.portal.Desktop', 'org.freedesktop.portal.FileChooser', '/org/freedesktop/portal/desktop', [
        ('OpenFile', [('parentWindow', 's'), ('title', 's'), ('options', 'a{sv}')], 'o'),
        ('SaveFile', [('parentWindow', 's'), ('title', 's'), ('options', 'a{sv}')], 'o'),
        ('SaveFiles', [('parentWindow', 's'), ('title', 's'), ('options', 'a{sv}')], 'o'),
    ], [
        ('version', 'u'),
    ], 'https://raw.githubusercontent.com/flatpak/xdg-desktop-portal/main/data/org.freedesktop.portal.FileChooser.xml', bus='session', swift_name='FreedesktopPortal.FileChooser')
    generate('FreedesktopPortal', 'FreedesktopPortalOpenURI', 'org.freedesktop.portal.Desktop', 'org.freedesktop.portal.OpenURI', '/org/freedesktop/portal/desktop', [
        ('OpenURI', [('parentWindow', 's'), ('uri', 's'), ('options', 'a{sv}')], 'o'),
        ('OpenFile', [('parentWindow', 's'), ('fd', 'h'), ('options', 'a{sv}')], 'o'),
        ('OpenDirectory', [('parentWindow', 's'), ('fd', 'h'), ('options', 'a{sv}')], 'o'),
        ('SchemeSupported', [('scheme', 's'), ('options', 'a{sv}')], 'b'),
    ], [
        ('version', 'u'),
    ], 'https://raw.githubusercontent.com/flatpak/xdg-desktop-portal/main/data/org.freedesktop.portal.OpenURI.xml', bus='session', swift_name='FreedesktopPortal.OpenURI')
    generate('FreedesktopPortal', 'FreedesktopPortalSettings', 'org.freedesktop.portal.Desktop', 'org.freedesktop.portal.Settings', '/org/freedesktop/portal/desktop', [
        ('ReadAll', [('namespaces', 'as')], 'a{sa{sv}}'),
        ('Read', [('namespace', 's'), ('key', 's')], 'v'),
        ('ReadOne', [('namespace', 's'), ('key', 's')], 'v'),
    ], [
        ('version', 'u'),
    ], 'https://raw.githubusercontent.com/flatpak/xdg-desktop-portal/main/data/org.freedesktop.portal.Settings.xml', bus='session', swift_name='FreedesktopPortal.Settings')
    generate('FreedesktopPortal', 'FreedesktopPortalScreenCast', 'org.freedesktop.portal.Desktop', 'org.freedesktop.portal.ScreenCast', '/org/freedesktop/portal/desktop', [
        ('CreateSession', [('options', 'a{sv}')], 'o'),
        ('SelectSources', [('sessionHandle', 'o'), ('options', 'a{sv}')], 'o'),
        ('Start', [('sessionHandle', 'o'), ('parentWindow', 's'), ('options', 'a{sv}')], 'o'),
        ('OpenPipeWireRemote', [('sessionHandle', 'o'), ('options', 'a{sv}')], 'h'),
    ], [
        ('AvailableSourceTypes', 'u'),
        ('AvailableCursorModes', 'u'),
        ('version', 'u'),
    ], 'https://raw.githubusercontent.com/flatpak/xdg-desktop-portal/main/data/org.freedesktop.portal.ScreenCast.xml', bus='session', swift_name='FreedesktopPortal.ScreenCast')
    generate('FreedesktopPortal', 'FreedesktopPortalRequest', 'org.freedesktop.portal.Desktop', 'org.freedesktop.portal.Request', None, [
        ('Close', [], ''),
    ], [
    ], 'https://raw.githubusercontent.com/flatpak/xdg-desktop-portal/main/data/org.freedesktop.portal.Request.xml', bus='session', swift_name='FreedesktopPortal.Request')
    generate('FreedesktopPortal', 'FreedesktopPortalSession', 'org.freedesktop.portal.Desktop', 'org.freedesktop.portal.Session', None, [
        ('Close', [], ''),
    ], [
        ('version', 'u'),
    ], 'https://raw.githubusercontent.com/flatpak/xdg-desktop-portal/main/data/org.freedesktop.portal.Session.xml', bus='session', swift_name='FreedesktopPortal.Session')
    generate('UDisks2', 'UDisks2', 'org.freedesktop.UDisks2', 'org.freedesktop.UDisks2.Manager', '/org/freedesktop/UDisks2/Manager', [
        ('CanFormat', [('type', 's')], '(bs)'),
        ('CanResize', [('type', 's')], '(bts)'),
        ('CanCheck', [('type', 's')], '(bs)'),
        ('CanRepair', [('type', 's')], '(bs)'),
        ('LoopSetup', [('fd', 'h'), ('options', 'a{sv}')], 'o'),
        ('MDRaidCreate', [('blocks', 'ao'), ('level', 's'), ('name', 's'), ('chunk', 't'), ('options', 'a{sv}')], 'o'),
        ('EnableModules', [('enable', 'b')], ''),
        ('EnableModule', [('name', 's'), ('enable', 'b')], ''),
        ('GetBlockDevices', [('options', 'a{sv}')], 'ao'),
        ('GetDrives', [('options', 'a{sv}')], 'ao'),
        ('ResolveDevice', [('devspec', 'a{sv}'), ('options', 'a{sv}')], 'ao'),
    ], [
        ('Version', 's'),
        ('SupportedFilesystems', 'as'),
        ('SupportedEncryptionTypes', 'as'),
        ('DefaultEncryptionType', 's'),
    ], 'https://raw.githubusercontent.com/storaged-project/udisks/master/data/org.freedesktop.UDisks2.xml', bus='system', swift_name='UDisks2.Manager')
    generate('UDisks2', 'UDisks2Drive', 'org.freedesktop.UDisks2', 'org.freedesktop.UDisks2.Drive', None, [
        ('Eject', [('options', 'a{sv}')], ''),
        ('SetConfiguration', [('value', 'a{sv}'), ('options', 'a{sv}')], ''),
        ('PowerOff', [('options', 'a{sv}')], ''),
    ], [
        ('Vendor', 's'),
        ('Model', 's'),
        ('Revision', 's'),
        ('Serial', 's'),
        ('WWN', 's'),
        ('Id', 's'),
        ('Configuration', 'a{sv}'),
        ('Media', 's'),
        ('MediaCompatibility', 'as'),
        ('MediaRemovable', 'b'),
        ('MediaAvailable', 'b'),
        ('MediaChangeDetected', 'b'),
        ('Size', 't'),
        ('TimeDetected', 't'),
        ('TimeMediaDetected', 't'),
        ('Optical', 'b'),
        ('OpticalBlank', 'b'),
        ('OpticalNumTracks', 'u'),
        ('OpticalNumAudioTracks', 'u'),
        ('OpticalNumDataTracks', 'u'),
        ('OpticalNumSessions', 'u'),
        ('RotationRate', 'i'),
        ('ConnectionBus', 's'),
        ('Seat', 's'),
        ('Removable', 'b'),
        ('Ejectable', 'b'),
        ('SortKey', 's'),
        ('CanPowerOff', 'b'),
        ('SiblingId', 's'),
    ], 'https://raw.githubusercontent.com/storaged-project/udisks/master/data/org.freedesktop.UDisks2.xml', bus='system', swift_name='UDisks2.Drive')
    generate('UDisks2', 'UDisks2Block', 'org.freedesktop.UDisks2', 'org.freedesktop.UDisks2.Block', None, [
        ('AddConfigurationItem', [('item', '(sa{sv})'), ('options', 'a{sv}')], ''),
        ('RemoveConfigurationItem', [('item', '(sa{sv})'), ('options', 'a{sv}')], ''),
        ('UpdateConfigurationItem', [('oldItem', '(sa{sv})'), ('newItem', '(sa{sv})'), ('options', 'a{sv}')], ''),
        ('GetSecretConfiguration', [('options', 'a{sv}')], 'a(sa{sv})'),
        ('Format', [('type', 's'), ('options', 'a{sv}')], ''),
        ('OpenForBackup', [('options', 'a{sv}')], 'h'),
        ('OpenForRestore', [('options', 'a{sv}')], 'h'),
        ('OpenForBenchmark', [('options', 'a{sv}')], 'h'),
        ('OpenDevice', [('mode', 's'), ('options', 'a{sv}')], 'h'),
        ('Rescan', [('options', 'a{sv}')], ''),
        ('RestoreEncryptedHeader', [('backupFile', 's'), ('options', 'a{sv}')], ''),
    ], [
        ('Device', 'ay'),
        ('PreferredDevice', 'ay'),
        ('Symlinks', 'aay'),
        ('DeviceNumber', 't'),
        ('Id', 's'),
        ('Size', 't'),
        ('ReadOnly', 'b'),
        ('Drive', 'o'),
        ('MDRaid', 'o'),
        ('MDRaidMember', 'o'),
        ('IdUsage', 's'),
        ('IdType', 's'),
        ('IdVersion', 's'),
        ('IdLabel', 's'),
        ('IdUUID', 's'),
        ('Configuration', 'a(sa{sv})'),
        ('CryptoBackingDevice', 'o'),
        ('HintPartitionable', 'b'),
        ('HintSystem', 'b'),
        ('HintIgnore', 'b'),
        ('HintAuto', 'b'),
        ('HintName', 's'),
        ('HintIconName', 's'),
        ('HintSymbolicIconName', 's'),
        ('UserspaceMountOptions', 'as'),
    ], 'https://raw.githubusercontent.com/storaged-project/udisks/master/data/org.freedesktop.UDisks2.xml', bus='system', swift_name='UDisks2.Block')
    generate('UDisks2', 'UDisks2Filesystem', 'org.freedesktop.UDisks2', 'org.freedesktop.UDisks2.Filesystem', None, [
        ('SetLabel', [('label', 's'), ('options', 'a{sv}')], ''),
        ('SetUUID', [('uuid', 's'), ('options', 'a{sv}')], ''),
        ('Mount', [('options', 'a{sv}')], 's'),
        ('Unmount', [('options', 'a{sv}')], ''),
        ('Resize', [('size', 't'), ('options', 'a{sv}')], ''),
        ('Check', [('options', 'a{sv}')], 'b'),
        ('Repair', [('options', 'a{sv}')], 'b'),
        ('TakeOwnership', [('options', 'a{sv}')], ''),
    ], [
        ('MountPoints', 'aay'),
        ('Size', 't'),
    ], 'https://raw.githubusercontent.com/storaged-project/udisks/master/data/org.freedesktop.UDisks2.xml', bus='system', swift_name='UDisks2.Filesystem')
    generate('UDisks2', 'UDisks2Partition', 'org.freedesktop.UDisks2', 'org.freedesktop.UDisks2.Partition', None, [
        ('SetType', [('type', 's'), ('options', 'a{sv}')], ''),
        ('SetName', [('name', 's'), ('options', 'a{sv}')], ''),
        ('SetUUID', [('uuid', 's'), ('options', 'a{sv}')], ''),
        ('SetFlags', [('flags', 't'), ('options', 'a{sv}')], ''),
        ('Resize', [('size', 't'), ('options', 'a{sv}')], ''),
        ('Delete', [('options', 'a{sv}')], ''),
    ], [
        ('Number', 'u'),
        ('Type', 's'),
        ('Flags', 't'),
        ('Offset', 't'),
        ('Size', 't'),
        ('Name', 's'),
        ('UUID', 's'),
        ('Table', 'o'),
        ('IsContainer', 'b'),
        ('IsContained', 'b'),
    ], 'https://raw.githubusercontent.com/storaged-project/udisks/master/data/org.freedesktop.UDisks2.xml', bus='system', swift_name='UDisks2.Partition')
    generate('UDisks2', 'UDisks2PartitionTable', 'org.freedesktop.UDisks2', 'org.freedesktop.UDisks2.PartitionTable', None, [
        ('CreatePartition', [('offset', 't'), ('size', 't'), ('type', 's'), ('name', 's'), ('options', 'a{sv}')], 'o'),
        ('CreatePartitionAndFormat', [('offset', 't'), ('size', 't'), ('type', 's'), ('name', 's'), ('options', 'a{sv}'), ('formatType', 's'), ('formatOptions', 'a{sv}')], 'o'),
    ], [
        ('Partitions', 'ao'),
        ('Type', 's'),
    ], 'https://raw.githubusercontent.com/storaged-project/udisks/master/data/org.freedesktop.UDisks2.xml', bus='system', swift_name='UDisks2.PartitionTable')
    generate('UDisks2', 'UDisks2Encrypted', 'org.freedesktop.UDisks2', 'org.freedesktop.UDisks2.Encrypted', None, [
        ('Unlock', [('passphrase', 's'), ('options', 'a{sv}')], 'o'),
        ('Lock', [('options', 'a{sv}')], ''),
        ('ChangePassphrase', [('passphrase', 's'), ('newPassphrase', 's'), ('options', 'a{sv}')], ''),
        ('Resize', [('size', 't'), ('options', 'a{sv}')], ''),
        ('Convert', [('targetVersion', 's'), ('options', 'a{sv}')], ''),
        ('HeaderBackup', [('backupFile', 's'), ('options', 'a{sv}')], ''),
    ], [
        ('ChildConfiguration', 'a(sa{sv})'),
        ('HintEncryptionType', 's'),
        ('MetadataSize', 't'),
        ('CleartextDevice', 'o'),
    ], 'https://raw.githubusercontent.com/storaged-project/udisks/master/data/org.freedesktop.UDisks2.xml', bus='system', swift_name='UDisks2.Encrypted')
    generate('UDisks2', 'UDisks2Loop', 'org.freedesktop.UDisks2', 'org.freedesktop.UDisks2.Loop', None, [
        ('Delete', [('options', 'a{sv}')], ''),
        ('SetAutoclear', [('value', 'b'), ('options', 'a{sv}')], ''),
        ('SetCapacity', [('options', 'a{sv}')], ''),
    ], [
        ('BackingFile', 'ay'),
        ('Autoclear', 'b'),
        ('SetupByUID', 'u'),
    ], 'https://raw.githubusercontent.com/storaged-project/udisks/master/data/org.freedesktop.UDisks2.xml', bus='system', swift_name='UDisks2.Loop')
    generate('UDisks2', 'UDisks2Swapspace', 'org.freedesktop.UDisks2', 'org.freedesktop.UDisks2.Swapspace', None, [
        ('Start', [('options', 'a{sv}')], ''),
        ('Stop', [('options', 'a{sv}')], ''),
        ('SetLabel', [('label', 's'), ('options', 'a{sv}')], ''),
        ('SetUUID', [('uuid', 's'), ('options', 'a{sv}')], ''),
    ], [
        ('Active', 'b'),
    ], 'https://raw.githubusercontent.com/storaged-project/udisks/master/data/org.freedesktop.UDisks2.xml', bus='system', swift_name='UDisks2.Swapspace')
    generate('UDisks2', 'UDisks2Job', 'org.freedesktop.UDisks2', 'org.freedesktop.UDisks2.Job', None, [
        ('Cancel', [('options', 'a{sv}')], ''),
    ], [
        ('Operation', 's'),
        ('Progress', 'd'),
        ('ProgressValid', 'b'),
        ('Bytes', 't'),
        ('Rate', 't'),
        ('StartTime', 't'),
        ('ExpectedEndTime', 't'),
        ('Objects', 'ao'),
        ('StartedByUID', 'u'),
        ('Cancelable', 'b'),
    ], 'https://raw.githubusercontent.com/storaged-project/udisks/master/data/org.freedesktop.UDisks2.xml', bus='system', swift_name='UDisks2.Job')


def _define_media_and_agents(generate):
    generate('MPRIS', 'MPRIS', None, 'org.mpris.MediaPlayer2', '/org/mpris/MediaPlayer2',
             [('Raise', [], ''), ('Quit', [], '')],
             [('CanQuit', 'b'), ('Fullscreen', 'b', 'readwrite'), ('CanSetFullscreen', 'b'),
              ('CanRaise', 'b'), ('HasTrackList', 'b'), ('Identity', 's'), ('DesktopEntry', 's'),
              ('SupportedUriSchemes', 'as'), ('SupportedMimeTypes', 'as')],
             'https://specifications.freedesktop.org/mpris/latest/Media_Player.html',
             bus='session', swift_name='MPRIS')
    generate('MPRIS', 'MPRISPlayer', None, 'org.mpris.MediaPlayer2.Player', '/org/mpris/MediaPlayer2',
             [(name, [], '') for name in ['Next', 'Previous', 'Pause', 'PlayPause', 'Stop', 'Play']] + [
                 ('Seek', [('offset', 'x')], ''),
                 ('SetPosition', [('trackID', 'o'), ('position', 'x')], ''),
                 ('OpenUri', [('uri', 's')], '')],
             [('PlaybackStatus', 's'), ('LoopStatus', 's', 'readwrite'), ('Rate', 'd', 'readwrite'),
              ('Shuffle', 'b', 'readwrite'), ('Metadata', 'a{sv}'), ('Volume', 'd', 'readwrite'),
              ('Position', 'x'), ('MinimumRate', 'd'), ('MaximumRate', 'd')] +
             [(name, 'b') for name in ['CanGoNext', 'CanGoPrevious', 'CanPlay', 'CanPause', 'CanSeek', 'CanControl']],
             'https://specifications.freedesktop.org/mpris/latest/Player_Interface.html',
             bus='session', swift_name='MPRIS.Player')
    generate('Polkit', 'Polkit', 'org.freedesktop.PolicyKit1', 'org.freedesktop.PolicyKit1.Authority',
             '/org/freedesktop/PolicyKit1/Authority', [
                 ('EnumerateActions', [('locale', 's')], 'a(ssssssuuua{ss})'),
                 ('CheckAuthorization', [('subject', '(sa{sv})'), ('actionID', 's'), ('details', 'a{ss}'),
                                         ('flags', 'u'), ('cancellationID', 's')], '(bba{ss})'),
                 ('CancelCheckAuthorization', [('cancellationID', 's')], ''),
                 ('RegisterAuthenticationAgent', [('subject', '(sa{sv})'), ('locale', 's'), ('objectPath', 's')], ''),
                 ('UnregisterAuthenticationAgent', [('subject', '(sa{sv})'), ('objectPath', 's')], ''),
                 ('AuthenticationAgentResponse', [('cookie', 's'), ('identity', '(sa{sv})')], ''),
                 ('AuthenticationAgentResponse2', [('uid', 'u'), ('cookie', 's'), ('identity', '(sa{sv})')], ''),
                 ('EnumerateTemporaryAuthorizations', [('subject', '(sa{sv})')], 'a(ss(sa{sv})tt)'),
                 ('RevokeTemporaryAuthorizations', [('subject', '(sa{sv})')], ''),
                 ('RevokeTemporaryAuthorizationById', [('id', 's')], '')],
             [('BackendName', 's'), ('BackendVersion', 's'), ('BackendFeatures', 'u')],
             'https://www.freedesktop.org/software/polkit/docs/latest/eggdbus-interface-org.freedesktop.PolicyKit1.Authority.html',
             swift_name='Polkit.Authority')
    generate('BlueZ', 'BlueZAgentManager', 'org.bluez', 'org.bluez.AgentManager1', '/org/bluez', [
        ('RegisterAgent', [('agent', 'o'), ('capability', 's')], ''),
        ('UnregisterAgent', [('agent', 'o')], ''),
        ('RequestDefaultAgent', [('agent', 'o')], '')], [],
        'https://bluez.readthedocs.io/en/latest/agent-api/')
    generate('BlueZ', 'BlueZAgent', None, 'org.bluez.Agent1', None, [
        ('Release', [], ''), ('RequestPinCode', [('device', 'o')], 's'),
        ('DisplayPinCode', [('device', 'o'), ('pinCode', 's')], ''),
        ('RequestPasskey', [('device', 'o')], 'u'),
        ('DisplayPasskey', [('device', 'o'), ('passkey', 'u'), ('entered', 'q')], ''),
        ('RequestConfirmation', [('device', 'o'), ('passkey', 'u')], ''),
        ('RequestAuthorization', [('device', 'o')], ''),
        ('AuthorizeService', [('device', 'o'), ('uuid', 's')], ''),
        ('Cancel', [], '')], [], 'https://bluez.readthedocs.io/en/latest/agent-api/', swift_name='BlueZ.Agent')
    generate('UDisks2', 'UDisks2ObjectManager', 'org.freedesktop.UDisks2',
             'org.freedesktop.DBus.ObjectManager', '/org/freedesktop/UDisks2',
             [('GetManagedObjects', [], 'a{oa{sa{sv}}}')], [],
             'https://storaged.org/doc/udisks2-api/latest/', swift_name='UDisks2.ObjectManager')
