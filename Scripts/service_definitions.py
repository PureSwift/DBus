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
