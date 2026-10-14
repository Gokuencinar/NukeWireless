"""Public Bonjour discovery types and permission text for every app variant."""
SERVICES = ["_airplay._tcp", "_raop._tcp", "_companion-link._tcp", "_apple-mobdev2._tcp",
            "_googlecast._tcp", "_androidtvremote2._tcp", "_smb._tcp", "_rdp._tcp",
            "_ssh._tcp", "_workstation._tcp", "_device-info._tcp", "_ipp._tcp",
            "_printer._tcp", "_http._tcp", "_hap._tcp"]
USAGE = "Discover device names on your Wi-Fi network / Identificar equipos en tu red Wi-Fi."

def apply(metadata):
    metadata.update(NSBonjourServices=SERVICES, NSLocalNetworkUsageDescription=USAGE)
    # UPnP device descriptions use local HTTP; keep ATS for other destinations.
    transport = dict(metadata.get('NSAppTransportSecurity', {}))
    transport['NSAllowsLocalNetworking'] = True
    metadata['NSAppTransportSecurity'] = transport
